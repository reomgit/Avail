import AvailCore
import AvailPlayback
import Foundation
import SwiftData
import XCTest
@testable import AvailApp

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!
    private var fixture: PlaybackFixture!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailPlaybackCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testPlayPauseResumeAndAutomaticNextChunk() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20, 20, 20])
        await fixture.coordinator.play(bookID: fixture.bookID)
        XCTAssertEqual(fixture.engine.spoken.map(\.chunk.id), [fixture.chunks[0].id])

        fixture.engine.emit(.started(chunkID: fixture.chunks[0].id))
        await settle()
        XCTAssertEqual(fixture.coordinator.state, .playing)

        fixture.coordinator.pause()
        fixture.coordinator.resume()
        XCTAssertEqual(fixture.engine.pauseCallCount, 1)
        XCTAssertEqual(fixture.engine.resumeCallCount, 1)

        fixture.engine.emit(.finished(chunkID: fixture.chunks[0].id))
        await settle()
        XCTAssertEqual(fixture.engine.spoken.map(\.chunk.id), [fixture.chunks[0].id, fixture.chunks[1].id])
    }

    func testStartingAnotherBookStopsPreviousSession() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20, 20])
        let secondBook = try await fixture.addBook(named: "Second", chunkWordCounts: [20])
        await fixture.coordinator.play(bookID: fixture.bookID)

        await fixture.coordinator.play(bookID: secondBook.bookID)

        XCTAssertEqual(fixture.engine.stopCallCount, 1)
        XCTAssertEqual(fixture.coordinator.currentBookID, secondBook.bookID)
        XCTAssertEqual(fixture.engine.spoken.last?.chunk.id, secondBook.chunks[0].id)
    }

    func testRangeUpdatesFollowHighlightAndDebouncedPersistenceWhilePauseFlushesImmediately() async throws {
        fixture = try await PlaybackFixture(
            sandbox: sandbox,
            chunkWordCounts: [20, 20],
            persistenceDebounce: .milliseconds(20)
        )
        await fixture.coordinator.play(bookID: fixture.bookID)
        let range = NSRange(location: 8, length: 5)
        fixture.engine.emit(.willSpeakRange(chunkID: fixture.chunks[0].id, range: range))
        await settle()

        XCTAssertEqual(fixture.coordinator.highlightedChunkID, fixture.chunks[0].id)
        XCTAssertEqual(fixture.coordinator.highlightRange, range)
        try await Task.sleep(for: .milliseconds(35))
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.utf16Offset, 8)

        fixture.engine.emit(.willSpeakRange(chunkID: fixture.chunks[0].id, range: NSRange(location: 18, length: 4)))
        await settle()
        fixture.coordinator.pause()
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.utf16Offset, 18)
    }

    func testMissingChunkIdentifierRestoresFromNormalizedWordOffset() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20, 20, 20])
        try fixture.libraryStore.savePlaybackPosition(
            ReadingPosition(
                bookID: fixture.bookID,
                sectionID: UUID(),
                chunkID: UUID(),
                utf16Offset: 12,
                normalizedWordOffset: 25,
                updatedAt: Date()
            )
        )

        await fixture.coordinator.play(bookID: fixture.bookID)

        XCTAssertEqual(fixture.engine.spoken.last?.chunk.id, fixture.chunks[1].id)
    }

    func testFifteenSecondSeekUsesRateAdjustedWordDeltaAndPersistsImmediately() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20, 20, 20])
        await fixture.coordinator.play(bookID: fixture.bookID)

        await fixture.coordinator.seek(by: 15)

        XCTAssertEqual(fixture.engine.spoken.last?.chunk.id, fixture.chunks[1].id)
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.normalizedWordOffset, 20)
    }

    func testChapterNavigationSkipsEmptySections() async throws {
        fixture = try await PlaybackFixture(
            sandbox: sandbox,
            chunkWordCounts: [20, 20],
            includeEmptyMiddleSection: true
        )
        await fixture.coordinator.play(bookID: fixture.bookID)

        await fixture.coordinator.nextChapter()

        XCTAssertEqual(fixture.engine.spoken.last?.chunk.id, fixture.chunks[1].id)
    }

    func testFrontierBuffersPrioritizesIndexingAndResumesAfterCommittedUpdate() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20], isIndexComplete: false)
        await fixture.coordinator.play(bookID: fixture.bookID)
        fixture.engine.emit(.finished(chunkID: fixture.chunks[0].id))
        await settle()

        XCTAssertEqual(fixture.coordinator.state, .bufferingForIndex)
        XCTAssertEqual(fixture.indexing.prioritizedBookIDs, [fixture.bookID])

        let appended = try await fixture.appendChunk(words: 20)
        fixture.indexing.emit(bookID: fixture.bookID, progress: IndexingProgress(phase: .playable, indexedWordCount: 40))
        await settle()

        XCTAssertEqual(fixture.engine.spoken.last?.chunk.id, appended.id)
    }

    func testVoiceFallbackIsSavedAndStopAndTerminationFlushCurrentPosition() async throws {
        fixture = try await PlaybackFixture(sandbox: sandbox, chunkWordCounts: [20, 20])
        let record = try XCTUnwrap(fixture.libraryStore.book(id: fixture.bookID))
        record.voiceIdentifier = "missing.voice"
        await fixture.coordinator.play(bookID: fixture.bookID)
        fixture.engine.emit(.voiceFallback(requestedIdentifier: "missing.voice", selectedIdentifier: "installed.voice"))
        fixture.engine.emit(.willSpeakRange(chunkID: fixture.chunks[0].id, range: NSRange(location: 10, length: 3)))
        await settle()

        fixture.coordinator.stop()
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.voiceIdentifier, "installed.voice")
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.utf16Offset, 10)

        fixture.engine.emit(.willSpeakRange(chunkID: fixture.chunks[0].id, range: NSRange(location: 14, length: 3)))
        await settle()
        fixture.coordinator.applicationWillTerminate()
        XCTAssertEqual(try fixture.libraryStore.book(id: fixture.bookID)?.utf16Offset, 14)
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
private final class PlaybackFixture {
    let sandbox: URL
    let libraryStore: LibraryStore
    let indexStore: ReadingIndexStore
    let engine = FakeNarrationEngine()
    let indexing = FakeIndexingPrioritizer()
    let nowPlaying = FakeNowPlayingController()
    let coordinator: PlaybackCoordinator
    private(set) var bookID: UUID
    private(set) var chunks: [SpeechChunk]
    private var nextBatchOrdinal = 1

    init(
        sandbox: URL,
        chunkWordCounts: [Int],
        includeEmptyMiddleSection: Bool = false,
        isIndexComplete: Bool = true,
        persistenceDebounce: Duration = .seconds(1)
    ) async throws {
        self.sandbox = sandbox
        let libraryURL = sandbox.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "PlaybackFixture-\(UUID().uuidString)")!
        let locationStore = LibraryLocationStore(defaults: defaults, creationOptions: [], resolutionOptions: [])
        try locationStore.select(libraryURL)
        let container = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        libraryStore = LibraryStore(modelContainer: container, locationStore: locationStore)
        indexStore = ReadingIndexStore(rootURL: sandbox.appending(path: "Indexes", directoryHint: .isDirectory))
        let created = try await Self.createBook(
            name: "First",
            chunkWordCounts: chunkWordCounts,
            includeEmptyMiddleSection: includeEmptyMiddleSection,
            complete: isIndexComplete,
            sandbox: sandbox,
            libraryStore: libraryStore,
            indexStore: indexStore
        )
        bookID = created.bookID
        chunks = created.chunks
        coordinator = PlaybackCoordinator(
            engine: engine,
            indexStore: indexStore,
            libraryStore: libraryStore,
            indexingCoordinator: indexing,
            nowPlaying: nowPlaying,
            persistenceDebounce: persistenceDebounce
        )
    }

    func addBook(named name: String, chunkWordCounts: [Int]) async throws -> (bookID: UUID, chunks: [SpeechChunk]) {
        try await Self.createBook(
            name: name,
            chunkWordCounts: chunkWordCounts,
            includeEmptyMiddleSection: false,
            complete: true,
            sandbox: sandbox,
            libraryStore: libraryStore,
            indexStore: indexStore
        )
    }

    func appendChunk(words: Int) async throws -> SpeechChunk {
        let locator = SourceLocator.pdf(pageIndex: chunks.count)
        let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: chunks.count)
        let chunk = Self.makeChunk(sectionID: sectionID, locator: locator, ordinal: chunks.count, words: words)
        let section = ReadingSection(id: sectionID, ordinal: chunks.count, title: "Chapter \(chunks.count + 1)", locator: locator, chunkIDs: [chunk.id])
        try await indexStore.commit(
            IndexBatch(ordinal: nextBatchOrdinal, sections: [section], chunks: [chunk], resumeLocator: locator),
            bookID: bookID
        )
        nextBatchOrdinal += 1
        chunks.append(chunk)
        return chunk
    }

    private static func createBook(
        name: String,
        chunkWordCounts: [Int],
        includeEmptyMiddleSection: Bool,
        complete: Bool,
        sandbox: URL,
        libraryStore: LibraryStore,
        indexStore: ReadingIndexStore
    ) async throws -> (bookID: UUID, chunks: [SpeechChunk]) {
        let source = sandbox.appending(path: "\(name)-\(UUID().uuidString).pdf")
        try Data(name.utf8).write(to: source)
        guard case let .created(bookID) = try await libraryStore.importBook(from: source) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var chunks: [SpeechChunk] = []
        var sections: [ReadingSection] = []
        for (index, words) in chunkWordCounts.enumerated() {
            let sectionOrdinal = includeEmptyMiddleSection && index > 0 ? index + 1 : index
            if includeEmptyMiddleSection && index == 1 {
                let emptyLocator = SourceLocator.pdf(pageIndex: 1)
                sections.append(
                    ReadingSection(id: UUID(), ordinal: 1, title: "Empty", locator: emptyLocator, chunkIDs: [])
                )
            }
            let locator = SourceLocator.pdf(pageIndex: sectionOrdinal)
            let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: sectionOrdinal)
            let chunk = makeChunk(sectionID: sectionID, locator: locator, ordinal: index, words: words)
            chunks.append(chunk)
            sections.append(
                ReadingSection(id: sectionID, ordinal: sectionOrdinal, title: "Chapter \(sectionOrdinal + 1)", locator: locator, chunkIDs: [chunk.id])
            )
        }
        let frontier = sections.last?.locator ?? .pdf(pageIndex: 0)
        try await indexStore.commit(IndexBatch(ordinal: 0, sections: sections, chunks: chunks, resumeLocator: frontier), bookID: bookID)
        if complete { try await indexStore.markComplete(bookID: bookID) }
        try libraryStore.applyIndexManifest(try await indexStore.manifest(bookID: bookID), bookID: bookID)
        return (bookID, chunks)
    }

    private static func makeChunk(
        sectionID: UUID,
        locator: SourceLocator,
        ordinal: Int,
        words: Int
    ) -> SpeechChunk {
        let text = (0..<words).map { "word\($0)" }.joined(separator: " ")
        return SpeechChunk(
            id: StableIdentifier.make(sectionID: sectionID, kind: "chunk", locator: locator, ordinal: ordinal),
            sectionID: sectionID,
            ordinal: ordinal,
            text: text,
            wordCount: words,
            locator: locator,
            sourceRange: SourceTextRange(utf16Location: 0, utf16Length: text.utf16.count)
        )
    }
}

@MainActor
private final class FakeNarrationEngine: NarrationEngine {
    let voices = [NarrationVoice(id: "installed.voice", name: "Installed", languageCode: "en-US")]
    let events: AsyncStream<NarrationEvent>
    private let continuation: AsyncStream<NarrationEvent>.Continuation
    private(set) var spoken: [NarrationRequest] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var stopCallCount = 0

    init() {
        (events, continuation) = AsyncStream.makeStream(of: NarrationEvent.self)
    }

    func speak(_ request: NarrationRequest) { spoken.append(request) }
    func pause() { pauseCallCount += 1 }
    func resume() { resumeCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func emit(_ event: NarrationEvent) { continuation.yield(event) }
}

@MainActor
private final class FakeIndexingPrioritizer: IndexingPrioritizing {
    let updates: AsyncStream<IndexingUpdate>
    private let continuation: AsyncStream<IndexingUpdate>.Continuation
    private(set) var prioritizedBookIDs: [UUID] = []

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: IndexingUpdate.self)
    }

    func prioritize(bookID: UUID, after locator: SourceLocator?) {
        prioritizedBookIDs.append(bookID)
    }

    func emit(bookID: UUID, progress: IndexingProgress) {
        continuation.yield(IndexingUpdate(bookID: bookID, progress: progress))
    }
}

@MainActor
private final class FakeNowPlayingController: NowPlayingControlling {
    private(set) var snapshots: [NowPlayingSnapshot] = []
    private(set) var states: [PlaybackState] = []
    func update(_ snapshot: NowPlayingSnapshot) { snapshots.append(snapshot) }
    func updatePlaybackState(_ state: PlaybackState) { states.append(state) }
    func installRemoteCommands(_ handlers: NowPlayingHandlers) {}
    func teardown() {}
}

import AvailCore
import AvailPlayback
import Foundation
import SwiftData
import XCTest
@testable import AvailApp

@MainActor
final class ZenViewModelTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!
    private var fixture: ZenFixture!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailZenTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testHighlightedUTF16RangeMapsOnlyToActiveChunk() async throws {
        fixture = try await ZenFixture(sandbox: sandbox)
        let model = fixture.makeModel()
        await model.load()
        await fixture.playback.play(bookID: fixture.bookID)
        let range = (fixture.chunks[0].text as NSString).range(of: "reader")
        fixture.engine.emit(.willSpeakRange(chunkID: fixture.chunks[0].id, range: range))
        await settle()

        XCTAssertEqual(model.highlightedSubstring(in: fixture.chunks[0]), "reader")
        XCTAssertNil(model.highlightedSubstring(in: fixture.chunks[1]))
    }

    func testManualScrollSuspendsFollowAndReturnRespectsReduceMotion() async throws {
        fixture = try await ZenFixture(sandbox: sandbox)
        let model = fixture.makeModel()
        await model.load()
        model.userDidScroll()

        XCTAssertFalse(model.isFollowingNarration)
        XCTAssertTrue(model.showsReturnToNarration)

        model.returnToNarration(reduceMotion: true)
        XCTAssertTrue(model.isFollowingNarration)
        XCTAssertEqual(model.scrollRequest?.animated, false)
    }

    func testClosingDoesNotStopPlaybackAndReopeningReconnects() async throws {
        fixture = try await ZenFixture(sandbox: sandbox)
        let first = fixture.makeModel()
        await first.load()
        await fixture.playback.play(bookID: fixture.bookID)
        let stopCount = fixture.engine.stopCallCount

        first.windowWillClose()
        let reopened = fixture.makeModel()
        await reopened.load()

        XCTAssertEqual(fixture.engine.stopCallCount, stopCount)
        XCTAssertTrue(reopened.isConnectedToActivePlayback)
        XCTAssertEqual(reopened.chunks.map(\.id), fixture.chunks.map(\.id))
    }

    func testActivePlaybackSharesChapterPresentationBeforeZenContentLoads() async throws {
        fixture = try await ZenFixture(sandbox: sandbox)
        let model = fixture.makeModel()

        await fixture.playback.play(bookID: fixture.bookID)

        XCTAssertEqual(model.currentChapterTitle, "Beginning")
    }

    func testVoiceAndRatePersistPerBook() async throws {
        fixture = try await ZenFixture(sandbox: sandbox)
        let model = fixture.makeModel()
        await model.load()

        model.setRate(1.5)
        model.setVoiceIdentifier("voice.en")

        let record = try XCTUnwrap(fixture.libraryStore.book(id: fixture.bookID))
        XCTAssertEqual(record.narrationRate, 1.5)
        XCTAssertEqual(record.voiceIdentifier, "voice.en")
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
private final class ZenFixture {
    let libraryStore: LibraryStore
    let indexStore: ReadingIndexStore
    let engine = ZenFakeNarrationEngine()
    let playback: PlaybackCoordinator
    let bookID: UUID
    let chunks: [SpeechChunk]

    init(sandbox: URL) async throws {
        let libraryURL = sandbox.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "AvailZenFixture-\(UUID().uuidString)")!
        let location = LibraryLocationStore(defaults: defaults, creationOptions: [], resolutionOptions: [])
        try location.select(libraryURL)
        let container = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        libraryStore = LibraryStore(
            modelContainer: container,
            locationStore: location,
            artworkStore: ArtworkStore(
                rootURL: sandbox.appending(path: "Artwork", directoryHint: .isDirectory)
            )
        )
        let source = sandbox.appending(path: "Zen.pdf")
        try Data("zen-book".utf8).write(to: source)
        guard case let .created(createdID) = try await libraryStore.importBook(from: source) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bookID = createdID
        indexStore = ReadingIndexStore(rootURL: sandbox.appending(path: "Indexes", directoryHint: .isDirectory))

        let firstLocator = SourceLocator.pdf(pageIndex: 0)
        let secondLocator = SourceLocator.pdf(pageIndex: 1)
        let firstSection = StableIdentifier.make(bookID: createdID, kind: "section", locator: firstLocator, ordinal: 0)
        let secondSection = StableIdentifier.make(bookID: createdID, kind: "section", locator: secondLocator, ordinal: 1)
        let first = Self.chunk(
            sectionID: firstSection,
            locator: firstLocator,
            ordinal: 0,
            text: "Hello 👋🏽 reader, this is the first chapter."
        )
        let second = Self.chunk(
            sectionID: secondSection,
            locator: secondLocator,
            ordinal: 1,
            text: "This second chapter keeps the narration moving."
        )
        chunks = [first, second]
        let sections = [
            ReadingSection(id: firstSection, ordinal: 0, title: "Beginning", locator: firstLocator, chunkIDs: [first.id]),
            ReadingSection(id: secondSection, ordinal: 1, title: "Next", locator: secondLocator, chunkIDs: [second.id]),
        ]
        try await indexStore.commit(
            IndexBatch(ordinal: 0, sections: sections, chunks: chunks, resumeLocator: secondLocator),
            bookID: createdID
        )
        try await indexStore.markComplete(bookID: createdID)
        try libraryStore.applyIndexManifest(try await indexStore.manifest(bookID: createdID), bookID: createdID)
        let indexing = ZenFakeIndexingPrioritizer()
        playback = PlaybackCoordinator(
            engine: engine,
            indexStore: indexStore,
            libraryStore: libraryStore,
            indexingCoordinator: indexing,
            nowPlaying: ZenFakeNowPlayingController()
        )
    }

    func makeModel() -> ZenViewModel {
        ZenViewModel(
            bookID: bookID,
            libraryStore: libraryStore,
            indexStore: indexStore,
            playback: playback
        )
    }

    private static func chunk(
        sectionID: UUID,
        locator: SourceLocator,
        ordinal: Int,
        text: String
    ) -> SpeechChunk {
        SpeechChunk(
            id: StableIdentifier.make(sectionID: sectionID, kind: "chunk", locator: locator, ordinal: ordinal),
            sectionID: sectionID,
            ordinal: ordinal,
            text: text,
            wordCount: text.split(whereSeparator: \.isWhitespace).count,
            locator: locator,
            sourceRange: SourceTextRange(utf16Location: 0, utf16Length: text.utf16.count)
        )
    }
}

@MainActor
private final class ZenFakeNarrationEngine: NarrationEngine {
    let voices = [NarrationVoice(id: "voice.en", name: "Local English", languageCode: "en-US")]
    let events: AsyncStream<NarrationEvent>
    private let continuation: AsyncStream<NarrationEvent>.Continuation
    private(set) var stopCallCount = 0
    init() { (events, continuation) = AsyncStream.makeStream(of: NarrationEvent.self) }
    func speak(_ request: NarrationRequest) {}
    func pause() {}
    func resume() {}
    func stop() { stopCallCount += 1 }
    func emit(_ event: NarrationEvent) { continuation.yield(event) }
}

@MainActor
private final class ZenFakeIndexingPrioritizer: IndexingPrioritizing {
    let updates: AsyncStream<IndexingUpdate>
    init() { updates = AsyncStream { _ in } }
    func prioritize(bookID: UUID, after locator: SourceLocator?) {}
}

@MainActor
private final class ZenFakeNowPlayingController: NowPlayingControlling {
    func update(_ snapshot: NowPlayingSnapshot) {}
    func updatePlaybackState(_ state: PlaybackState) {}
    func installRemoteCommands(_ handlers: NowPlayingHandlers) {}
    func teardown() {}
}

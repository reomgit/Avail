import AvailCore
import AvailPlayback
import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testFreshEnvironmentNeedsLibraryLocation() {
        let subject = AppEnvironment.bootstrapForTesting()

        XCTAssertNil(subject.selectedBookID)
        XCTAssertEqual(subject.launchState, .needsLibraryLocation)
    }

    func testSelectingPopulatedLibraryStartsIndexingDiscoveredBook() async throws {
        let subject = AppEnvironment.bootstrapForTesting()
        let library = FileManager.default.temporaryDirectory
            .appending(path: "AvailEnvironmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("not-a-real-pdf".utf8).write(to: library.appending(path: "Existing.pdf"))

        await subject.selectLibraryLocation(library)

        let book = try XCTUnwrap(subject.libraryStore?.books().first)
        XCTAssertNotNil(subject.indexingCoordinator?.progress(for: book.id))
        await subject.indexingCoordinator?.waitUntilFinished(bookID: book.id)
    }

    func testRemovingActiveBookClearsPlaybackRecordAndDerivedIndex() async throws {
        let engine = EnvironmentFakeNarrationEngine()
        let nowPlaying = EnvironmentFakeNowPlayingController()
        let subject = AppEnvironment.bootstrapForTesting(
            narrationEngine: engine,
            nowPlayingController: nowPlaying
        )
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvailEnvironmentRemoval-\(UUID().uuidString)", directoryHint: .isDirectory)
        let library = root.appending(path: "Library", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try subject.locationStore.select(library)

        let source = root.appending(path: "Removal.pdf")
        try Data("remove-me".utf8).write(to: source)
        guard case let .created(bookID) = try await subject.libraryStore?.importBook(from: source) else {
            return XCTFail("Expected a new record")
        }

        let locator = SourceLocator.pdf(pageIndex: 0)
        let sectionID = StableIdentifier.make(
            bookID: bookID,
            kind: "section",
            locator: locator,
            ordinal: 0
        )
        let text = "A passage that should stop before its book is removed."
        let chunk = SpeechChunk(
            id: StableIdentifier.make(
                sectionID: sectionID,
                kind: "chunk",
                locator: locator,
                ordinal: 0
            ),
            sectionID: sectionID,
            ordinal: 0,
            text: text,
            wordCount: text.split(whereSeparator: \.isWhitespace).count,
            locator: locator,
            sourceRange: SourceTextRange(
                utf16Location: 0,
                utf16Length: text.utf16.count
            )
        )
        let section = ReadingSection(
            id: sectionID,
            ordinal: 0,
            title: "Removal",
            locator: locator,
            chunkIDs: [chunk.id]
        )
        let indexStore = try XCTUnwrap(subject.indexStore)
        try await indexStore.commit(
            IndexBatch(ordinal: 0, sections: [section], chunks: [chunk], resumeLocator: locator),
            bookID: bookID
        )
        try await indexStore.markComplete(bookID: bookID)
        try subject.libraryStore?.applyIndexManifest(
            await indexStore.manifest(bookID: bookID),
            bookID: bookID
        )
        subject.selectedBookID = bookID
        await subject.playbackCoordinator?.play(bookID: bookID)

        try await subject.removeBook(bookID: bookID, mode: .recordOnly)

        XCTAssertEqual(engine.stopCallCount, 1)
        XCTAssertEqual(subject.playbackCoordinator?.state, .stopped)
        XCTAssertNil(subject.playbackCoordinator?.currentBookID)
        XCTAssertNil(subject.playbackCoordinator?.currentChunk)
        XCTAssertEqual(nowPlaying.states.last, .stopped)
        XCTAssertNil(subject.selectedBookID)
        XCTAssertNil(try subject.libraryStore?.book(id: bookID))
        let remainingChunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
        XCTAssertTrue(remainingChunks.isEmpty)
    }
}

@MainActor
private final class EnvironmentFakeNarrationEngine: NarrationEngine {
    let voices: [NarrationVoice] = []
    let events: AsyncStream<NarrationEvent>
    private(set) var stopCallCount = 0

    init() {
        events = AsyncStream { _ in }
    }

    func speak(_ request: NarrationRequest) {}
    func pause() {}
    func resume() {}
    func stop() { stopCallCount += 1 }
}

@MainActor
private final class EnvironmentFakeNowPlayingController: NowPlayingControlling {
    private(set) var states: [PlaybackState] = []

    func update(_ snapshot: NowPlayingSnapshot) {}
    func updatePlaybackState(_ state: PlaybackState) { states.append(state) }
    func installRemoteCommands(_ handlers: NowPlayingHandlers) {}
    func teardown() {}
}

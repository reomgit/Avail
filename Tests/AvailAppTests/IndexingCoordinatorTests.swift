import AvailCore
import Foundation
import SwiftData
import XCTest
@testable import AvailApp

@MainActor
final class IndexingCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!
    nonisolated(unsafe) private var libraryURL: URL!
    private var libraryStore: LibraryStore!
    private var bookID: UUID!
    private var indexStore: ReadingIndexStore!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        libraryURL = sandbox.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testCommitsBatchesBeforeCrossingPlayableThresholdAndCompletes() async throws {
        try await prepareBook()
        let batches = [makeBatch(ordinal: 0, words: 200), makeBatch(ordinal: 1, words: 300)]
        let factory = FakeIndexerFactory(events: [
            .metadata(BookMetadata(title: "Indexed Title", authors: ["Author"], languageCode: "en")),
            .batch(batches[0]),
            .batch(batches[1]),
            .completed(totalWords: 500, sectionCount: 2),
        ])
        let coordinator = IndexingCoordinator(
            libraryStore: libraryStore,
            indexStore: indexStore,
            indexerFactory: factory
        )

        coordinator.start(bookID: bookID)
        await coordinator.waitUntilFinished(bookID: bookID)

        let manifest = try await indexStore.manifest(bookID: bookID)
        let record = try XCTUnwrap(libraryStore.book(id: bookID))
        XCTAssertEqual(manifest.indexedWordCount, 500)
        XCTAssertTrue(manifest.isComplete)
        XCTAssertEqual(record.indexedWordCount, 500)
        XCTAssertTrue(record.isPlayable)
        XCTAssertTrue(record.isIndexComplete)
        XCTAssertEqual(record.state, .ready)
        XCTAssertEqual(record.title, "Indexed Title")
        XCTAssertEqual(record.author, "Author")
        XCTAssertEqual(coordinator.progress(for: bookID)?.phase, .complete)
    }

    func testTwoHundredCommittedWordsRemainIndexing() async throws {
        try await prepareBook()
        let coordinator = IndexingCoordinator(
            libraryStore: libraryStore,
            indexStore: indexStore,
            indexerFactory: FakeIndexerFactory(events: [.batch(makeBatch(ordinal: 0, words: 200))])
        )

        coordinator.start(bookID: bookID)
        await coordinator.waitUntilFinished(bookID: bookID)

        XCTAssertEqual(coordinator.progress(for: bookID)?.phase, .indexing)
        XCTAssertFalse(try XCTUnwrap(libraryStore.book(id: bookID)).isPlayable)
    }

    func testFiveHundredCommittedWordsBecomePlayableBeforeCompletion() async throws {
        try await prepareBook()
        let coordinator = IndexingCoordinator(
            libraryStore: libraryStore,
            indexStore: indexStore,
            indexerFactory: FakeIndexerFactory(events: [.batch(makeBatch(ordinal: 0, words: 500))])
        )

        coordinator.start(bookID: bookID)
        await coordinator.waitUntilFinished(bookID: bookID)

        XCTAssertEqual(coordinator.progress(for: bookID)?.phase, .playable)
        let record = try XCTUnwrap(libraryStore.book(id: bookID))
        XCTAssertTrue(record.isPlayable)
        XCTAssertFalse(record.isIndexComplete)
        XCTAssertEqual(record.state, .indexing)
    }

    func testRestartPassesLastCommittedFrontierToIndexer() async throws {
        try await prepareBook()
        let committed = makeBatch(ordinal: 0, words: 200)
        _ = try await indexStore.prepare(bookID: bookID)
        try await indexStore.commit(committed, bookID: bookID)
        let recorder = ResumeRecorder()
        let coordinator = IndexingCoordinator(
            libraryStore: libraryStore,
            indexStore: indexStore,
            indexerFactory: FakeIndexerFactory(events: [], recorder: recorder)
        )

        coordinator.start(bookID: bookID)
        await coordinator.waitUntilFinished(bookID: bookID)

        let recordedLocator = await recorder.lastLocator
        XCTAssertEqual(recordedLocator, committed.resumeLocator)
    }

    func testIndexerFailurePersistsSpecificFailureState() async throws {
        try await prepareBook()
        let coordinator = IndexingCoordinator(
            libraryStore: libraryStore,
            indexStore: indexStore,
            indexerFactory: FakeIndexerFactory(events: [], terminalError: FakeFailure.broken)
        )

        coordinator.start(bookID: bookID)
        await coordinator.waitUntilFinished(bookID: bookID)

        let record = try XCTUnwrap(libraryStore.book(id: bookID))
        XCTAssertEqual(record.state, .failed)
        XCTAssertNotNil(record.lastErrorDescription)
        XCTAssertEqual(coordinator.progress(for: bookID)?.phase, .failed)
    }

    private func prepareBook() async throws {
        let defaults = UserDefaults(suiteName: "AvailCoordinatorTests-\(UUID().uuidString)")!
        let locationStore = LibraryLocationStore(defaults: defaults, creationOptions: [], resolutionOptions: [])
        try locationStore.select(libraryURL)
        let container = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        libraryStore = LibraryStore(modelContainer: container, locationStore: locationStore)
        let source = sandbox.appending(path: "Book.epub")
        try Data("book".utf8).write(to: source)
        guard case let .created(createdID) = try await libraryStore.importBook(from: source) else {
            return XCTFail("Expected created book")
        }
        bookID = createdID
        indexStore = ReadingIndexStore(rootURL: sandbox.appending(path: "Indexes", directoryHint: .isDirectory))
    }

    private func makeBatch(ordinal: Int, words: Int) -> IndexBatch {
        let locator = SourceLocator.epub(spineIndex: ordinal, href: "chapter-\(ordinal).xhtml")
        let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: ordinal)
        let chunk = SpeechChunk(
            id: StableIdentifier.make(sectionID: sectionID, kind: "chunk", locator: locator, ordinal: 0),
            sectionID: sectionID,
            ordinal: 0,
            text: "Chunk \(ordinal)",
            wordCount: words,
            locator: locator,
            sourceRange: SourceTextRange(utf16Location: 0, utf16Length: 7)
        )
        let section = ReadingSection(
            id: sectionID,
            ordinal: ordinal,
            title: "Chapter \(ordinal + 1)",
            locator: locator,
            chunkIDs: [chunk.id]
        )
        return IndexBatch(ordinal: ordinal, sections: [section], chunks: [chunk], resumeLocator: locator)
    }
}

private struct FakeIndexerFactory: IndexerProviding {
    let events: [IndexingEvent]
    var terminalError: (any Error & Sendable)?
    var recorder: ResumeRecorder?

    init(
        events: [IndexingEvent],
        recorder: ResumeRecorder? = nil,
        terminalError: (any Error & Sendable)? = nil
    ) {
        self.events = events
        self.recorder = recorder
        self.terminalError = terminalError
    }

    func indexer(for format: BookFormat) -> any DocumentIndexer {
        FakeIndexer(events: events, terminalError: terminalError, recorder: recorder)
    }
}

private struct FakeIndexer: DocumentIndexer {
    let eventsToSend: [IndexingEvent]
    let terminalError: (any Error & Sendable)?
    let recorder: ResumeRecorder?

    init(
        events: [IndexingEvent],
        terminalError: (any Error & Sendable)?,
        recorder: ResumeRecorder?
    ) {
        self.eventsToSend = events
        self.terminalError = terminalError
        self.recorder = recorder
    }

    func events(
        for fileURL: URL,
        bookID: UUID,
        resumeAfter: SourceLocator?
    ) -> AsyncThrowingStream<IndexingEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recorder?.record(resumeAfter)
                for event in eventsToSend { continuation.yield(event) }
                if let terminalError {
                    continuation.finish(throwing: terminalError)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

private actor ResumeRecorder {
    private(set) var lastLocator: SourceLocator?
    func record(_ locator: SourceLocator?) { lastLocator = locator }
}

private enum FakeFailure: Error, Sendable {
    case broken
}

import XCTest
@testable import AvailCore

final class ReadingIndexStoreTests: XCTestCase, @unchecked Sendable {
    private var rootURL: URL!
    private let bookID = UUID(uuidString: "30000000-0000-0000-0000-000000000000")!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "AvailIndexTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testPrepareCreatesAnEmptyCurrentManifest() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)

        let manifest = try await store.prepare(bookID: bookID)

        XCTAssertEqual(manifest, IndexManifest())
    }

    func testCommitMakesBatchVisibleAndIsIdempotent() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)
        let batch = makeBatch(ordinal: 0, words: [200, 300], page: 0)
        _ = try await store.prepare(bookID: bookID)

        try await store.commit(batch, bookID: bookID)
        try await store.commit(batch, bookID: bookID)

        let manifest = try await store.manifest(bookID: bookID)
        XCTAssertEqual(manifest.batchFiles, ["batch-000000.json"])
        XCTAssertEqual(manifest.indexedWordCount, 500)
        XCTAssertEqual(manifest.playableFrontier, .pdf(pageIndex: 0))
        let chunks = try await store.chunks(bookID: bookID, around: nil, limit: 10)
        XCTAssertEqual(chunks, batch.chunks)
    }

    func testRecoverRemovesTemporaryAndUncommittedBatchFiles() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)
        _ = try await store.prepare(bookID: bookID)
        let directory = rootURL.appending(path: bookID.uuidString, directoryHint: .isDirectory)
        try Data("partial".utf8).write(to: directory.appending(path: "manifest.json.tmp"))
        try JSONEncoder().encode(makeBatch(ordinal: 9, words: [10], page: 9))
            .write(to: directory.appending(path: "batch-000009.json"))

        let manifest = try await store.recover(bookID: bookID)

        XCTAssertEqual(manifest, IndexManifest())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "manifest.json.tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "batch-000009.json").path))
    }

    func testSchemaMismatchDiscardsDerivedBatches() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)
        let batch = makeBatch(ordinal: 0, words: [450], page: 0)
        _ = try await store.prepare(bookID: bookID)
        try await store.commit(batch, bookID: bookID)
        let directory = rootURL.appending(path: bookID.uuidString, directoryHint: .isDirectory)
        let stale = IndexManifest(
            schemaVersion: IndexManifest.currentSchemaVersion + 1,
            batchFiles: ["batch-000000.json"],
            indexedWordCount: 450,
            playableFrontier: .pdf(pageIndex: 0),
            isComplete: true
        )
        try JSONEncoder().encode(stale).write(to: directory.appending(path: "manifest.json"), options: .atomic)

        let manifest = try await store.prepare(bookID: bookID)

        XCTAssertEqual(manifest, IndexManifest())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "batch-000000.json").path))
    }

    func testWordOffsetLookupAndForwardChunkLoading() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)
        let first = makeBatch(ordinal: 0, words: [100, 200], page: 0)
        let second = makeBatch(ordinal: 1, words: [300], page: 1)
        _ = try await store.prepare(bookID: bookID)
        try await store.commit(first, bookID: bookID)
        try await store.commit(second, bookID: bookID)

        let position = try await store.position(bookID: bookID, normalizedWordOffset: 350)
        let forward = try await store.chunks(bookID: bookID, around: first.chunks[1].id, limit: 2)

        XCTAssertEqual(position?.chunk.id, second.chunks[0].id)
        XCTAssertEqual(position?.wordOffsetWithinChunk, 50)
        XCTAssertEqual(position?.globalWordOffset, 300)
        XCTAssertEqual(forward.map(\.id), [first.chunks[1].id, second.chunks[0].id])
    }

    func testMarkCompleteAndDiscard() async throws {
        let store = ReadingIndexStore(rootURL: rootURL)
        _ = try await store.prepare(bookID: bookID)
        try await store.commit(makeBatch(ordinal: 0, words: [450], page: 0), bookID: bookID)

        try await store.markComplete(bookID: bookID)
        let completed = try await store.manifest(bookID: bookID)
        XCTAssertTrue(completed.isComplete)

        try await store.discard(bookID: bookID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appending(path: bookID.uuidString).path))
    }

    private func makeBatch(ordinal: Int, words: [Int], page: Int) -> IndexBatch {
        let locator = SourceLocator.pdf(pageIndex: page)
        let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: page)
        let chunks = words.enumerated().map { chunkOrdinal, wordCount in
            SpeechChunk(
                id: StableIdentifier.make(sectionID: sectionID, kind: "chunk", locator: locator, ordinal: chunkOrdinal),
                sectionID: sectionID,
                ordinal: chunkOrdinal,
                text: "chunk-\(ordinal)-\(chunkOrdinal)",
                wordCount: wordCount,
                locator: locator,
                sourceRange: SourceTextRange(utf16Location: 0, utf16Length: 10)
            )
        }
        let section = ReadingSection(
            id: sectionID,
            ordinal: page,
            title: "Page \(page + 1)",
            locator: locator,
            chunkIDs: chunks.map(\.id)
        )
        return IndexBatch(ordinal: ordinal, sections: [section], chunks: chunks, resumeLocator: locator)
    }
}

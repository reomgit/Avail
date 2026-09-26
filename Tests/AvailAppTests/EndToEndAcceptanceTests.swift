import AppKit
import AvailCore
import AvailEPUB
import AvailPDF
import AvailPlayback
import CoreGraphics
import CoreText
import Foundation
import SwiftData
import XCTest
import ZIPFoundation
@testable import AvailApp

@MainActor
final class EndToEndAcceptanceTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailAcceptance-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testGeneratedEPUBBecomesPlayableBeforeCompletionAndExactCursorSurvivesCoordinatorReconstruction() async throws {
        let services = try makeServices()
        let source = try makeEPUB()
        guard case let .created(bookID) = try await services.library.importBook(from: source) else {
            return XCTFail("Expected imported EPUB")
        }
        let access = try services.library.accessBookFile(bookID: bookID)
        var batches: [IndexBatch] = []
        var completionIndex: Int?
        var firstPlayableEventIndex: Int?
        var eventIndex = 0
        var committedWords = 0

        for try await event in EPUBIndexer().events(for: access.url, bookID: bookID, resumeAfter: nil) {
            switch event {
            case let .metadata(metadata):
                try await services.library.applyMetadata(metadata, bookID: bookID)
            case let .batch(batch):
                batches.append(batch)
                committedWords += batch.chunks.reduce(0) { $0 + $1.wordCount }
                if committedWords >= 450, firstPlayableEventIndex == nil { firstPlayableEventIndex = eventIndex }
            case .completed:
                completionIndex = eventIndex
            }
            eventIndex += 1
        }

        XCTAssertNotNil(firstPlayableEventIndex)
        XCTAssertLessThan(try XCTUnwrap(firstPlayableEventIndex), try XCTUnwrap(completionIndex))

        try await services.indexes.commit(batches[0], bookID: bookID)
        try services.library.applyIndexManifest(try await services.indexes.manifest(bookID: bookID), bookID: bookID)
        let progressiveRecord = try XCTUnwrap(services.library.book(id: bookID))
        XCTAssertTrue(progressiveRecord.isPlayable)
        XCTAssertFalse(progressiveRecord.isIndexComplete)

        for batch in batches.dropFirst() { try await services.indexes.commit(batch, bookID: bookID) }
        try await services.indexes.markComplete(bookID: bookID)
        try services.library.applyIndexManifest(try await services.indexes.manifest(bookID: bookID), bookID: bookID)

        let firstEngine = AcceptanceNarrationEngine()
        let firstPlayback = makePlayback(engine: firstEngine, services: services)
        await firstPlayback.play(bookID: bookID)
        let firstRequest = try XCTUnwrap(firstEngine.spoken.first)
        let spokenRange = NSRange(location: 17, length: 8)
        firstEngine.emit(.willSpeakRange(chunkID: firstRequest.chunk.id, range: spokenRange))
        await settle()
        firstPlayback.pause()

        let secondEngine = AcceptanceNarrationEngine()
        let reconstructed = makePlayback(engine: secondEngine, services: services)
        await reconstructed.play(bookID: bookID)
        let resumed = try XCTUnwrap(secondEngine.spoken.first)
        XCTAssertEqual(resumed.chunk.id, firstRequest.chunk.id)
        XCTAssertEqual(resumed.startUTF16Offset, spokenRange.location)

        secondEngine.emit(.finished(chunkID: resumed.chunk.id))
        await settle()
        let spokenIDs = secondEngine.spoken.map(\.chunk.id)
        XCTAssertEqual(Set(spokenIDs).count, spokenIDs.count)
    }

    func testGeneratedThreeHundredPagePDFIndexesEveryPageWithBoundedBatches() async throws {
        let url = try makePDF(pageCount: 300)
        let bookID = UUID()
        var batches: [IndexBatch] = []
        var completedSections = 0

        for try await event in PDFIndexer().events(for: url, bookID: bookID, resumeAfter: nil) {
            if case let .batch(batch) = event { batches.append(batch) }
            if case let .completed(_, sectionCount) = event { completedSections = sectionCount }
        }

        XCTAssertEqual(completedSections, 300)
        XCTAssertEqual(batches.flatMap(\.sections).count, 300)
        XCTAssertTrue(batches.allSatisfy { $0.chunks.count <= 50 })
    }

    func testProductionSourcesContainNoNetworkOrAnalyticsClient() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            repository.appending(path: "Avail", directoryHint: .isDirectory),
            repository.appending(path: "Modules", directoryHint: .isDirectory),
        ]
        let swiftFiles = sourceRoots.flatMap { directory in
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [URL]() }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        let networkClientFiles = try swiftFiles.filter {
            try String(contentsOf: $0, encoding: .utf8).contains("URLSession")
        }.map { $0.lastPathComponent }

        XCTAssertEqual(networkClientFiles, ["LocalSpeechServerClient.swift"])
        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(contents.contains("import Network"), file.lastPathComponent)
            XCTAssertFalse(contents.contains("Analytics"), file.lastPathComponent)
            XCTAssertFalse(contents.contains("Telemetry"), file.lastPathComponent)
        }
    }

    private func makeServices() throws -> AcceptanceServices {
        let libraryURL = sandbox.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "AvailAcceptance-\(UUID().uuidString)")!
        let locations = LibraryLocationStore(defaults: defaults, creationOptions: [], resolutionOptions: [])
        try locations.select(libraryURL)
        let container = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return AcceptanceServices(
            library: LibraryStore(
                modelContainer: container,
                locationStore: locations,
                artworkStore: ArtworkStore(
                    rootURL: sandbox.appending(path: "Artwork", directoryHint: .isDirectory)
                )
            ),
            indexes: ReadingIndexStore(rootURL: sandbox.appending(path: "Indexes", directoryHint: .isDirectory))
        )
    }

    private func makePlayback(engine: AcceptanceNarrationEngine, services: AcceptanceServices) -> PlaybackCoordinator {
        PlaybackCoordinator(
            engine: engine,
            indexStore: services.indexes,
            libraryStore: services.library,
            indexingCoordinator: AcceptanceIndexingPrioritizer(),
            nowPlaying: AcceptanceNowPlayingController(),
            persistenceDebounce: .milliseconds(5)
        )
    }

    private func makeEPUB() throws -> URL {
        let sentence = "Local narration keeps every word and document private on this Mac. "
        let chapter = String(repeating: sentence, count: 180)
        let entries: [(String, Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            (
                "META-INF/container.xml",
                Data(
                    """
                    <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
                    """.utf8)
            ),
            (
                "OEBPS/content.opf",
                Data(
                    """
                    <package version="3.0" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
                      <metadata><dc:title>Acceptance EPUB</dc:title><dc:creator>Avail Tests</dc:creator><dc:language>en</dc:language></metadata>
                      <manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest>
                      <spine><itemref idref="one"/><itemref idref="two"/></spine>
                    </package>
                    """.utf8)
            ),
            ("OEBPS/one.xhtml", Data("<html><body><h1>One</h1><p>\(chapter)</p></body></html>".utf8)),
            ("OEBPS/two.xhtml", Data("<html><body><h1>Two</h1><p>\(chapter)</p></body></html>".utf8)),
        ]
        let archive = try Archive(accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                provider: { position, size in
                    let lower = Int(position)
                    return data.subdata(in: lower..<lower + size)
                }
            )
        }
        let url = sandbox.appending(path: "Acceptance.epub")
        try archive.data?.write(to: url)
        return url
    }

    private func makePDF(pageCount: Int) throws -> URL {
        let url = sandbox.appending(path: "Acceptance-300.pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw CocoaError(.fileWriteUnknown) }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            let text = "Page \(page + 1). Local selectable text for offline narration."
            let attributed = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func settle() async {
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(3))
    }
}

private struct AcceptanceServices {
    let library: LibraryStore
    let indexes: ReadingIndexStore
}

@MainActor
private final class AcceptanceNarrationEngine: NarrationEngine {
    let voices = [NarrationVoice(id: "acceptance.voice", name: "Acceptance", languageCode: "en-US")]
    let events: AsyncStream<NarrationEvent>
    private let continuation: AsyncStream<NarrationEvent>.Continuation
    private(set) var spoken: [NarrationRequest] = []
    init() { (events, continuation) = AsyncStream.makeStream(of: NarrationEvent.self) }
    func speak(_ request: NarrationRequest) { spoken.append(request) }
    func pause() {}
    func resume() {}
    func stop() {}
    func emit(_ event: NarrationEvent) { continuation.yield(event) }
}

@MainActor
private final class AcceptanceIndexingPrioritizer: IndexingPrioritizing {
    let updates: AsyncStream<IndexingUpdate>
    init() { updates = AsyncStream { _ in } }
    func prioritize(bookID: UUID, after locator: SourceLocator?) {}
}

@MainActor
private final class AcceptanceNowPlayingController: NowPlayingControlling {
    func update(_ snapshot: NowPlayingSnapshot) {}
    func updatePlaybackState(_ state: PlaybackState) {}
    func installRemoteCommands(_ handlers: NowPlayingHandlers) {}
    func teardown() {}
}

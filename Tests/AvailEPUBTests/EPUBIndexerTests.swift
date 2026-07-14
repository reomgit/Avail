import AvailCore
import ZIPFoundation
import XCTest
@testable import AvailEPUB

final class EPUBIndexerTests: XCTestCase, @unchecked Sendable {
    private var temporaryDirectory: URL!
    private let bookID = UUID(uuidString: "40000000-0000-0000-0000-000000000000")!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AvailEPUBTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testEPUB3StreamsMetadataSpineOrderedSectionsAndCleanText() async throws {
        let url = try makeEPUB(
            version: "3.0",
            title: "A Local Book",
            author: "Ada Reader",
            language: "en",
            chapters: [
                ("one.xhtml", "<h1>First</h1><p>Hello <em>local</em> listener.</p><script>bad()</script>"),
                ("two.xhtml", "<h1>Second</h1><p hidden>Hidden words.</p><p>Next chapter text.</p>"),
            ],
            includeNavigation: true,
            coverData: Data([0x01, 0x02, 0x03])
        )

        let events = try await collectEvents(from: url)

        guard case let .metadata(metadata) = events.first else {
            return XCTFail("Metadata must be the first event")
        }
        XCTAssertEqual(metadata.title, "A Local Book")
        XCTAssertEqual(metadata.authors, ["Ada Reader"])
        XCTAssertEqual(metadata.languageCode, "en")
        XCTAssertEqual(metadata.coverData, Data([0x01, 0x02, 0x03]))

        let batches = events.compactMap { event -> IndexBatch? in
            guard case let .batch(batch) = event else { return nil }
            return batch
        }
        XCTAssertEqual(batches.flatMap(\.sections).map(\.title), ["First", "Second"])
        let spoken = batches.flatMap(\.chunks).map(\.text).joined(separator: " ")
        XCTAssertTrue(spoken.contains("Hello local listener."))
        XCTAssertTrue(spoken.contains("Next chapter text."))
        XCTAssertFalse(spoken.contains("bad()"))
        XCTAssertFalse(spoken.contains("Hidden words"))
        guard case let .completed(totalWords, sectionCount) = events.last else {
            return XCTFail("Completion must be the final event")
        }
        XCTAssertGreaterThan(totalWords, 0)
        XCTAssertEqual(sectionCount, 2)
    }

    func testEPUB2NCXAndMalformedHTMLRemainReadable() async throws {
        let url = try makeEPUB(
            version: "2.0",
            title: "Legacy Book",
            author: nil,
            language: nil,
            chapters: [
                ("legacy.xhtml", "<html><body><h2>Legacy Chapter<p>Unclosed but readable &amp; useful."),
            ],
            includeNavigation: true
        )

        let events = try await collectEvents(from: url)
        let batches = events.compactMap { event -> IndexBatch? in
            guard case let .batch(batch) = event else { return nil }
            return batch
        }

        XCTAssertEqual(batches.flatMap(\.sections).first?.title, "Legacy Chapter Unclosed but readable & useful.")
        XCTAssertTrue(batches.flatMap(\.chunks).map(\.text).joined().contains("Unclosed but readable & useful."))
    }

    func testMissingMetadataFallsBackToFilename() async throws {
        let url = try makeEPUB(
            version: "3.0",
            title: nil,
            author: nil,
            language: nil,
            chapters: [("chapter.xhtml", "<p>Readable content.</p>")]
        )

        let events = try await collectEvents(from: url)
        guard case let .metadata(metadata) = events.first else {
            return XCTFail("Expected metadata")
        }
        XCTAssertEqual(metadata.title, url.deletingPathExtension().lastPathComponent)
    }

    func testEncryptedEPUBIsRejected() async throws {
        let url = try makeEPUB(
            version: "3.0",
            title: "Encrypted",
            author: nil,
            language: nil,
            chapters: [("chapter.xhtml", "<p>Secret.</p>")],
            encrypted: true
        )

        do {
            _ = try await collectEvents(from: url)
            XCTFail("Expected encryption rejection")
        } catch let error as EPUBError {
            XCTAssertEqual(error, .encrypted)
        }
    }

    func testEmptySpineIsRejected() async throws {
        let url = try makeEPUB(
            version: "3.0",
            title: "Empty",
            author: nil,
            language: nil,
            chapters: [("chapter.xhtml", "<style>body { color: red }</style><script>nothing()</script>")]
        )

        do {
            _ = try await collectEvents(from: url)
            XCTFail("Expected empty spine rejection")
        } catch let error as EPUBError {
            XCTAssertEqual(error, .emptySpine)
        }
    }

    func testResumeAfterSpineLocatorSkipsCommittedChapter() async throws {
        let url = try makeEPUB(
            version: "3.0",
            title: "Resume",
            author: nil,
            language: nil,
            chapters: [
                ("one.xhtml", "<h1>One</h1><p>Already committed.</p>"),
                ("two.xhtml", "<h1>Two</h1><p>Resume here.</p>"),
            ]
        )
        let stream = EPUBIndexer().events(
            for: url,
            bookID: bookID,
            resumeAfter: .epub(spineIndex: 0, href: "Text/one.xhtml")
        )

        var batches: [IndexBatch] = []
        for try await event in stream {
            if case let .batch(batch) = event { batches.append(batch) }
        }

        XCTAssertEqual(batches.flatMap(\.sections).map(\.title), ["Two"])
    }

    func testLargeChapterBatchesAtFiftyChunksAndResumesWithinSpine() async throws {
        let sentence = "A sentence with enough words to create stable narration chunks for progressive indexing. "
        let url = try makeEPUB(
            version: "3.0",
            title: "Large",
            author: nil,
            language: "en",
            chapters: [("large.xhtml", "<h1>Large Chapter</h1><p>\(String(repeating: sentence, count: 1_200))</p>")]
        )
        let allEvents = try await collectEvents(from: url)
        let allBatches = allEvents.compactMap { event -> IndexBatch? in
            guard case let .batch(batch) = event else { return nil }
            return batch
        }

        XCTAssertGreaterThan(allBatches.count, 1)
        XCTAssertTrue(allBatches.allSatisfy { $0.chunks.count <= 50 })
        guard case .epubProgress = allBatches[0].resumeLocator else {
            return XCTFail("The first partial batch needs an in-spine frontier")
        }

        var resumedChunks: [SpeechChunk] = []
        for try await event in EPUBIndexer().events(
            for: url,
            bookID: bookID,
            resumeAfter: allBatches[0].resumeLocator
        ) {
            if case let .batch(batch) = event { resumedChunks.append(contentsOf: batch.chunks) }
        }
        let allChunks = allBatches.flatMap(\.chunks)
        XCTAssertEqual(resumedChunks.map(\.id), Array(allChunks.dropFirst(allBatches[0].chunks.count)).map(\.id))
    }

    private func collectEvents(from url: URL) async throws -> [IndexingEvent] {
        var result: [IndexingEvent] = []
        for try await event in EPUBIndexer().events(for: url, bookID: bookID, resumeAfter: nil) {
            result.append(event)
        }
        return result
    }

    private func makeEPUB(
        version: String,
        title: String?,
        author: String?,
        language: String?,
        chapters: [(name: String, html: String)],
        includeNavigation: Bool = false,
        encrypted: Bool = false,
        coverData: Data? = nil
    ) throws -> URL {
        var entries: [(String, Data)] = []
        entries.append(("mimetype", Data("application/epub+zip".utf8)))
        entries.append(("META-INF/container.xml", Data("""
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8)))

        var metadata = ""
        if let title { metadata += "<dc:title>\(title)</dc:title>" }
        if let author { metadata += "<dc:creator>\(author)</dc:creator>" }
        if let language { metadata += "<dc:language>\(language)</dc:language>" }
        var manifest = chapters.enumerated().map { index, chapter in
            "<item id=\"c\(index)\" href=\"Text/\(chapter.name)\" media-type=\"application/xhtml+xml\"/>"
        }.joined()
        let spine = chapters.indices.map { "<itemref idref=\"c\($0)\"/>" }.joined()

        if includeNavigation, version.hasPrefix("3") {
            manifest += "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
            entries.append(("OEBPS/nav.xhtml", Data("<nav epub:type=\"toc\"><ol><li><a href=\"Text/\(chapters[0].name)\">Start</a></li></ol></nav>".utf8)))
        } else if includeNavigation {
            manifest += "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>"
            entries.append(("OEBPS/toc.ncx", Data("<ncx><navMap><navPoint><navLabel><text>Start</text></navLabel><content src=\"Text/\(chapters[0].name)\"/></navPoint></navMap></ncx>".utf8)))
        }
        if let coverData {
            manifest += "<item id=\"cover\" href=\"Images/cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>"
            entries.append(("OEBPS/Images/cover.jpg", coverData))
        }

        entries.append(("OEBPS/content.opf", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="\(version)" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata>\(metadata)</metadata>
          <manifest>\(manifest)</manifest>
          <spine>\(spine)</spine>
        </package>
        """.utf8)))

        for chapter in chapters {
            entries.append(("OEBPS/Text/\(chapter.name)", Data("<html><body>\(chapter.html)</body></html>".utf8)))
        }
        if encrypted {
            entries.append(("META-INF/encryption.xml", Data("<encryption/>".utf8)))
        }

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
        let url = temporaryDirectory.appending(path: "\(UUID().uuidString).epub")
        try archive.data?.write(to: url)
        return url
    }
}

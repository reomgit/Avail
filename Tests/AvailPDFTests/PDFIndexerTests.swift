import AppKit
import AvailCore
import CoreGraphics
import CoreText
import PDFKit
import XCTest
@testable import AvailPDF

final class PDFIndexerTests: XCTestCase, @unchecked Sendable {
    private var temporaryDirectory: URL!
    private let bookID = UUID(uuidString: "50000000-0000-0000-0000-000000000000")!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AvailPDFTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testStreamsMetadataAndSelectableTextInPageOrderWhileSkippingEmptyPage() async throws {
        let url = try makePDF(
            pages: ["First page text.", nil, "Third page text."],
            title: "A PDF Book",
            author: "Paige Turner"
        )

        let events = try await collectEvents(from: url)

        guard case let .metadata(metadata) = events.first else {
            return XCTFail("Metadata should be first")
        }
        XCTAssertEqual(metadata.title, "A PDF Book")
        XCTAssertEqual(metadata.authors, ["Paige Turner"])
        let batches = events.compactMap { event -> IndexBatch? in
            guard case let .batch(batch) = event else { return nil }
            return batch
        }
        XCTAssertEqual(batches.flatMap(\.sections).map(\.title), ["Page 1", "Page 3"])
        XCTAssertEqual(batches.flatMap(\.chunks).map(\.text), ["First page text.", "Third page text."])
        guard case let .completed(totalWords, sectionCount) = events.last else {
            return XCTFail("Completion should be last")
        }
        XCTAssertGreaterThan(totalWords, 0)
        XCTAssertEqual(sectionCount, 2)
    }

    func testImageOnlyPDFIsRejected() async throws {
        let url = try makePDF(pages: [nil, nil], title: "Scanned")

        do {
            _ = try await collectEvents(from: url)
            XCTFail("Expected no-selectable-text error")
        } catch let error as PDFIndexingError {
            XCTAssertEqual(error, .noSelectableText)
        }
    }

    func testLockedPDFIsRejected() async throws {
        let url = try makePDF(pages: ["Protected text."], title: "Locked", password: "secret")

        do {
            _ = try await collectEvents(from: url)
            XCTFail("Expected locked error")
        } catch let error as PDFIndexingError {
            XCTAssertEqual(error, .locked)
        }
    }

    func testResumeAfterPageSkipsCommittedPages() async throws {
        let url = try makePDF(pages: ["First.", "Second.", "Third."], title: "Resume")
        var batches: [IndexBatch] = []
        for try await event in PDFIndexer().events(
            for: url,
            bookID: bookID,
            resumeAfter: .pdf(pageIndex: 1)
        ) {
            if case let .batch(batch) = event { batches.append(batch) }
        }

        XCTAssertEqual(batches.flatMap(\.sections).map(\.title), ["Page 3"])
        XCTAssertEqual(batches.flatMap(\.chunks).map(\.text), ["Third."])
    }

    func testMetadataReaderMapsOutlineLabelToPage() throws {
        let url = try makePDF(pages: ["Chapter content."], title: "Outlined")
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else {
            return XCTFail("Expected fixture document")
        }
        let root = PDFOutline()
        let child = PDFOutline()
        child.label = "Chapter One"
        child.action = PDFActionGoTo(destination: PDFDestination(page: page, at: .zero))
        root.insertChild(child, at: 0)
        document.outlineRoot = root

        XCTAssertEqual(PDFMetadataReader().outlineTitles(for: document), [0: "Chapter One"])
    }

    func testLargePageUsesFiftyChunkBatchesAndInPageResumeFrontier() async throws {
        let sentence = "Progressive PDF narration uses a stable sentence for deterministic testing. "
        let url = try makePDF(
            pages: [String(repeating: sentence, count: 1_200)],
            title: "Large PDF"
        )
        let events = try await collectEvents(from: url)
        let batches = events.compactMap { event -> IndexBatch? in
            guard case let .batch(batch) = event else { return nil }
            return batch
        }

        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertTrue(batches.allSatisfy { $0.chunks.count <= 50 })
        guard case .pdfProgress = batches[0].resumeLocator else {
            return XCTFail("Expected an in-page frontier")
        }
    }

    private func collectEvents(from url: URL) async throws -> [IndexingEvent] {
        var result: [IndexingEvent] = []
        for try await event in PDFIndexer().events(for: url, bookID: bookID, resumeAfter: nil) {
            result.append(event)
        }
        return result
    }

    private func makePDF(
        pages: [String?],
        title: String? = nil,
        author: String? = nil,
        password: String? = nil
    ) throws -> URL {
        let url = temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw FixtureError.creationFailed
        }
        let longestTextCount = pages.compactMap { $0?.count }.max() ?? 0
        let estimatedLines = max(1, longestTextCount / 80 + 1)
        let pageHeight = max(792, CGFloat(estimatedLines * 16 + 144))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: pageHeight)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        if let author { info[kCGPDFContextAuthor] = author }
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = "owner-\(password)"
        }
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw FixtureError.creationFailed
        }

        for text in pages {
            context.beginPDFPage(nil)
            if let text {
                draw(text, in: context, pageHeight: pageHeight)
            } else {
                context.setFillColor(NSColor.systemGray.cgColor)
                context.fill(CGRect(x: 72, y: 72, width: 200, height: 120))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    private func draw(_ text: String, in context: CGContext, pageHeight: CGFloat) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 72, y: 72, width: 468, height: pageHeight - 144),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        CTFrameDraw(frame, context)
    }

}

private enum FixtureError: Error {
    case creationFailed
}

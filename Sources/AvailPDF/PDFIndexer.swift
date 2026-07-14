import AvailCore
import Foundation
import PDFKit

public struct PDFIndexer: DocumentIndexer {
    private let chunker: TextChunker

    public init(chunker: TextChunker = TextChunker()) {
        self.chunker = chunker
    }

    public func events(
        for fileURL: URL,
        bookID: UUID,
        resumeAfter: SourceLocator?
    ) -> AsyncThrowingStream<IndexingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    try index(fileURL: fileURL, bookID: bookID, resumeAfter: resumeAfter, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: PDFIndexingError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func index(
        fileURL: URL,
        bookID: UUID,
        resumeAfter: SourceLocator?,
        continuation: AsyncThrowingStream<IndexingEvent, Error>.Continuation
    ) throws {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: fileURL) else { throw PDFIndexingError.unreadable }
        guard !document.isLocked else { throw PDFIndexingError.locked }

        let metadataReader = PDFMetadataReader()
        continuation.yield(.metadata(metadataReader.metadata(for: document, fileURL: fileURL)))
        let outlineTitles = metadataReader.outlineTitles(for: document)
        let resume = PDFResumePoint(locator: resumeAfter)
        var totalWords = 0
        var readableSections = 0

        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()
            let pageText: String? = autoreleasepool {
                document.page(at: pageIndex)?.string
            }
            guard let text = pageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                continue
            }

            let locator = SourceLocator.pdf(pageIndex: pageIndex)
            let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: pageIndex)
            let chunks = chunker.chunks(from: text, sectionID: sectionID, locator: locator)
            guard !chunks.isEmpty else { continue }
            readableSections += 1
            totalWords += chunks.reduce(into: 0) { $0 += $1.wordCount }

            guard pageIndex >= resume.pageIndex else { continue }
            if resume.completedPage, pageIndex == resume.pageIndex { continue }
            let startChunk = pageIndex == resume.pageIndex ? min(resume.nextChunkOrdinal, chunks.count) : 0
            guard startChunk < chunks.count else { continue }

            let section = ReadingSection(
                id: sectionID,
                ordinal: pageIndex,
                title: outlineTitles[pageIndex] ?? "Page \(pageIndex + 1)",
                locator: locator,
                chunkIDs: chunks.map(\.id)
            )
            var sliceStart = startChunk
            while sliceStart < chunks.count {
                try Task.checkCancellation()
                let sliceEnd = min(sliceStart + 50, chunks.count)
                let sliceIndex = sliceStart / 50
                let frontier: SourceLocator = sliceEnd == chunks.count
                    ? locator
                    : .pdfProgress(pageIndex: pageIndex, nextChunkOrdinal: sliceEnd)
                continuation.yield(.batch(IndexBatch(
                    ordinal: pageIndex * 10_000 + sliceIndex,
                    sections: sliceStart == 0 ? [section] : [],
                    chunks: Array(chunks[sliceStart..<sliceEnd]),
                    resumeLocator: frontier
                )))
                sliceStart = sliceEnd
            }
        }

        guard readableSections > 0 else { throw PDFIndexingError.noSelectableText }
        continuation.yield(.completed(totalWords: totalWords, sectionCount: readableSections))
    }
}

private struct PDFResumePoint {
    let pageIndex: Int
    let nextChunkOrdinal: Int
    let completedPage: Bool

    init(locator: SourceLocator?) {
        switch locator {
        case let .pdf(pageIndex):
            self.pageIndex = pageIndex
            self.nextChunkOrdinal = 0
            self.completedPage = true
        case let .pdfProgress(pageIndex, nextChunkOrdinal):
            self.pageIndex = pageIndex
            self.nextChunkOrdinal = nextChunkOrdinal
            self.completedPage = false
        default:
            self.pageIndex = 0
            self.nextChunkOrdinal = 0
            self.completedPage = false
        }
    }
}

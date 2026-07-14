import AvailCore
import Foundation

public struct EPUBIndexer: DocumentIndexer {
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
        let archive: EPUBArchiveReader
        do {
            archive = try EPUBArchiveReader(url: fileURL)
        } catch {
            throw EPUBError.invalidContainer
        }
        guard !archive.contains("META-INF/encryption.xml") else { throw EPUBError.encrypted }

        let packageParser = EPUBPackageParser()
        let packagePath = try packageParser.packagePath(in: archive)
        guard archive.contains(packagePath) else { throw EPUBError.missingPackage }
        let package = try packageParser.parsePackage(
            data: try archive.data(at: packagePath, maximumSize: 5 * 1_024 * 1_024),
            packagePath: packagePath
        )
        let coverData = try package.coverPath.flatMap { path in
            try archive.data(at: path, maximumSize: 20 * 1_024 * 1_024)
        }
        continuation.yield(
            .metadata(
                BookMetadata(
                    title: package.title ?? fileURL.deletingPathExtension().lastPathComponent,
                    authors: package.authors,
                    languageCode: package.languageCode,
                    coverData: coverData
                )))

        let resume = ResumePoint(locator: resumeAfter)
        let contentParser = EPUBContentParser()
        var totalWords = 0
        var readableSections = 0

        for (spineIndex, itemID) in package.spineIDs.enumerated() {
            try Task.checkCancellation()
            guard let item = package.manifest[itemID], item.mediaType.contains("html") else { continue }
            let locator = SourceLocator.epub(spineIndex: spineIndex, href: item.path)
            let content = try contentParser.parse(data: archive.data(at: item.path), path: item.path)
            let sectionID = StableIdentifier.make(bookID: bookID, kind: "section", locator: locator, ordinal: spineIndex)
            let chunks = chunker.chunks(from: content.text, sectionID: sectionID, locator: locator)
            guard !chunks.isEmpty else { continue }
            readableSections += 1
            totalWords += chunks.reduce(into: 0) { $0 += $1.wordCount }

            guard spineIndex >= resume.spineIndex else { continue }
            if resume.completedSpine, spineIndex == resume.spineIndex { continue }
            let startChunk = spineIndex == resume.spineIndex ? min(resume.nextChunkOrdinal, chunks.count) : 0
            guard startChunk < chunks.count else { continue }

            let section = ReadingSection(
                id: sectionID,
                ordinal: spineIndex,
                title: content.title,
                locator: locator,
                chunkIDs: chunks.map(\.id)
            )
            var sliceStart = startChunk
            while sliceStart < chunks.count {
                try Task.checkCancellation()
                let sliceEnd = min(sliceStart + 50, chunks.count)
                let sliceIndex = sliceStart / 50
                let frontier: SourceLocator =
                    sliceEnd == chunks.count
                    ? locator
                    : .epubProgress(spineIndex: spineIndex, href: item.path, nextChunkOrdinal: sliceEnd)
                continuation.yield(
                    .batch(
                        IndexBatch(
                            ordinal: spineIndex * 10_000 + sliceIndex,
                            sections: sliceStart == 0 ? [section] : [],
                            chunks: Array(chunks[sliceStart..<sliceEnd]),
                            resumeLocator: frontier
                        )))
                sliceStart = sliceEnd
            }
        }

        guard readableSections > 0 else { throw EPUBError.emptySpine }
        continuation.yield(.completed(totalWords: totalWords, sectionCount: readableSections))
    }
}

private struct ResumePoint {
    let spineIndex: Int
    let nextChunkOrdinal: Int
    let completedSpine: Bool

    init(locator: SourceLocator?) {
        switch locator {
        case let .epub(spineIndex, _):
            self.spineIndex = spineIndex
            self.nextChunkOrdinal = 0
            self.completedSpine = true
        case let .epubProgress(spineIndex, _, nextChunkOrdinal):
            self.spineIndex = spineIndex
            self.nextChunkOrdinal = nextChunkOrdinal
            self.completedSpine = false
        default:
            self.spineIndex = 0
            self.nextChunkOrdinal = 0
            self.completedSpine = false
        }
    }
}

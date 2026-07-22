import Foundation

public enum IndexingEvent: Sendable {
    case metadata(BookMetadata)
    case batch(IndexBatch)
    case completed(totalWords: Int, sectionCount: Int)
}

public protocol DocumentIndexer: Sendable {
    func events(
        for fileURL: URL,
        bookID: UUID,
        resumeAfter: SourceLocator?
    ) -> AsyncThrowingStream<IndexingEvent, Error>
}

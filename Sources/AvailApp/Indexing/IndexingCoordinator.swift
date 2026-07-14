import AvailCore
import Foundation
import Observation

@MainActor
@Observable
final class IndexingCoordinator {
    private let libraryStore: LibraryStore
    private let indexStore: ReadingIndexStore
    private let indexerFactory: any IndexerProviding
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private(set) var progressByBookID: [UUID: IndexingProgress] = [:]

    init(
        libraryStore: LibraryStore,
        indexStore: ReadingIndexStore,
        indexerFactory: any IndexerProviding = IndexerFactory()
    ) {
        self.libraryStore = libraryStore
        self.indexStore = indexStore
        self.indexerFactory = indexerFactory
    }

    func progress(for bookID: UUID) -> IndexingProgress? {
        progressByBookID[bookID]
    }

    func start(bookID: UUID) {
        tasks[bookID]?.cancel()
        do {
            guard let record = try libraryStore.book(id: bookID) else { throw LibraryError.missingRecord }
            let access = try libraryStore.accessBookFile(bookID: bookID)
            let indexer = indexerFactory.indexer(for: record.format)
            progressByBookID[bookID] = IndexingProgress(phase: .readingMetadata)
            tasks[bookID] = Task { [weak self] in
                guard let self else { return }
                await self.run(bookID: bookID, access: access, indexer: indexer)
            }
        } catch {
            recordFailure(error, bookID: bookID)
        }
    }

    func cancel(bookID: UUID) {
        tasks.removeValue(forKey: bookID)?.cancel()
    }

    func retry(bookID: UUID) {
        start(bookID: bookID)
    }

    func prioritize(bookID: UUID, after locator: SourceLocator?) {
        let lowerPriorityBookIDs = tasks.keys.filter { $0 != bookID }
        for otherBookID in lowerPriorityBookIDs {
            tasks.removeValue(forKey: otherBookID)?.cancel()
        }
        if tasks[bookID] == nil {
            start(bookID: bookID)
        }
        _ = locator
    }

    func waitUntilFinished(bookID: UUID) async {
        await tasks[bookID]?.value
    }

    private func run(
        bookID: UUID,
        access: LibraryBookAccess,
        indexer: any DocumentIndexer
    ) async {
        do {
            let recovered = try await indexStore.recover(bookID: bookID)
            try libraryStore.applyIndexManifest(recovered, bookID: bookID)
            progressByBookID[bookID] = progress(
                from: recovered,
                completedSourceUnits: 0,
                phase: recovered.indexedWordCount >= 450 ? .playable : .indexing
            )

            var completedSourceUnits = 0
            let stream = indexer.events(
                for: access.url,
                bookID: bookID,
                resumeAfter: recovered.playableFrontier
            )
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case let .metadata(metadata):
                    try libraryStore.applyMetadata(metadata, bookID: bookID)
                case let .batch(batch):
                    try await indexStore.commit(batch, bookID: bookID)
                    let committed = try await indexStore.manifest(bookID: bookID)
                    if batch.resumeLocator.completesSourceUnit { completedSourceUnits += 1 }
                    try libraryStore.applyIndexManifest(committed, bookID: bookID)
                    progressByBookID[bookID] = progress(
                        from: committed,
                        completedSourceUnits: completedSourceUnits,
                        phase: committed.indexedWordCount >= 450 ? .playable : .indexing
                    )
                case let .completed(totalWords, sectionCount):
                    try await indexStore.markComplete(bookID: bookID)
                    let completed = try await indexStore.manifest(bookID: bookID)
                    try libraryStore.applyIndexManifest(completed, bookID: bookID)
                    progressByBookID[bookID] = IndexingProgress(
                        phase: .complete,
                        completedSourceUnits: sectionCount,
                        totalSourceUnits: sectionCount,
                        indexedWordCount: max(totalWords, completed.indexedWordCount),
                        playableFrontier: completed.playableFrontier
                    )
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { recordFailure(error, bookID: bookID) }
        }
    }

    private func progress(
        from manifest: IndexManifest,
        completedSourceUnits: Int,
        phase: IndexingPhase
    ) -> IndexingProgress {
        IndexingProgress(
            phase: phase,
            completedSourceUnits: completedSourceUnits,
            indexedWordCount: manifest.indexedWordCount,
            playableFrontier: manifest.playableFrontier
        )
    }

    private func recordFailure(_ error: Error, bookID: UUID) {
        let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        try? libraryStore.markIndexingFailure(bookID: bookID, description: description)
        var current = progressByBookID[bookID] ?? IndexingProgress()
        current.phase = .failed
        current.errorDescription = description
        progressByBookID[bookID] = current
    }
}

private extension SourceLocator {
    var completesSourceUnit: Bool {
        switch self {
        case .epub, .pdf:
            true
        case .epubProgress, .pdfProgress:
            false
        }
    }
}

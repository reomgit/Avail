import AvailCore
import Foundation

@MainActor
final class PlaybackPersistence {
    private let libraryStore: LibraryStore
    private let debounce: Duration
    private var pendingPosition: ReadingPosition?
    private var saveTask: Task<Void, Never>?

    init(libraryStore: LibraryStore, debounce: Duration = .seconds(1)) {
        self.libraryStore = libraryStore
        self.debounce = debounce
    }

    func schedule(_ position: ReadingPosition) {
        pendingPosition = position
        saveTask?.cancel()
        saveTask = Task { [weak self, debounce] in
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                self?.flush()
            } catch {
                return
            }
        }
    }

    func flush(_ position: ReadingPosition? = nil) {
        if let position { pendingPosition = position }
        saveTask?.cancel()
        saveTask = nil
        guard let pendingPosition else { return }
        try? libraryStore.savePlaybackPosition(pendingPosition)
        self.pendingPosition = nil
    }
}

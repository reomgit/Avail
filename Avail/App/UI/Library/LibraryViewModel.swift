import Foundation
import Observation

enum LibraryCollection: String, CaseIterable, Identifiable {
    case allBooks
    case continueListening
    case preparing

    var id: Self { self }
}

enum LibraryRoute: Hashable {
    case book(UUID)
}

struct BookStatePresentation: Equatable {
    let label: String
    let systemImage: String
    let accessibilityValue: String

    init(state: LibraryBookState) {
        switch state {
        case .copying:
            (label, systemImage) = ("Copying", "doc.on.doc")
        case .indexing:
            (label, systemImage) = ("Preparing", "text.magnifyingglass")
        case .ready:
            (label, systemImage) = ("Ready", "checkmark.circle")
        case .playing:
            (label, systemImage) = ("Listening", "waveform")
        case .missing:
            (label, systemImage) = ("File Missing", "exclamationmark.triangle")
        case .failed:
            (label, systemImage) = ("Needs Attention", "xmark.octagon")
        }
        accessibilityValue = label
    }
}

@MainActor
@Observable
final class LibraryViewModel {
    var collection: LibraryCollection = .allBooks
    var selectedBookID: UUID?
    var path: [LibraryRoute] = []
    var searchText = ""
    var isImporting = false

    func openBook(_ bookID: UUID) {
        selectedBookID = bookID
        path = [.book(bookID)]
    }

    func selectCollection(_ collection: LibraryCollection) {
        self.collection = collection
        selectedBookID = nil
        path.removeAll()
    }

    func canImport(launchState: AppEnvironment.LaunchState) -> Bool {
        launchState == .ready
    }

    func canPlay(_ book: LibraryBookRecord?) -> Bool {
        guard let book, book.state != .missing, book.state != .failed else { return false }
        return book.isPlayable
    }

    func continueListeningBookID(in books: [LibraryBookRecord]) -> UUID? {
        books
            .filter {
                $0.positionUpdatedAt != nil
                    && $0.state != .missing
                    && $0.state != .failed
                    && $0.isPlayable
            }
            .max { ($0.positionUpdatedAt ?? .distantPast) < ($1.positionUpdatedAt ?? .distantPast) }?
            .id
    }

    func filteredBooks(_ books: [LibraryBookRecord]) -> [LibraryBookRecord] {
        let scoped: [LibraryBookRecord]
        switch collection {
        case .allBooks:
            scoped = books
        case .continueListening:
            if let id = continueListeningBookID(in: books) {
                scoped = books.filter { $0.id == id }
            } else {
                scoped = []
            }
        case .preparing:
            scoped = books.filter { $0.state == .copying || $0.state == .indexing }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}

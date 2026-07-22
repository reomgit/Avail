import AvailCore
import Foundation
import Observation

@MainActor
@Observable
final class BookDetailViewModel {
    private(set) var book: LibraryBookRecord?
    private(set) var sections: [ReadingSection] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(
        bookID: UUID,
        libraryStore: LibraryStore?,
        indexStore: ReadingIndexStore?
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let libraryStore,
                let indexStore,
                let record = try libraryStore.book(id: bookID)
            else {
                throw LibraryError.missingRecord
            }
            book = record
            sections = try await indexStore.sections(bookID: bookID)
                .sorted { $0.ordinal < $1.ordinal }
            errorMessage = nil
        } catch {
            book = nil
            sections = []
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }

    func refreshSections(bookID: UUID, indexStore: ReadingIndexStore?) async {
        guard let indexStore else { return }
        do {
            sections = try await indexStore.sections(bookID: bookID)
                .sorted { $0.ordinal < $1.ordinal }
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }
}

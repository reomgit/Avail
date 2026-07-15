import Foundation

struct PlaybackBarPresentation: Equatable {
    let bookID: UUID
    let title: String
    let author: String
    let chapterTitle: String?
    let statusText: String?
    let isPlaying: Bool
    let canSeek: Bool

    var primaryActionLabel: String {
        isPlaying ? "Pause" : "Play"
    }

    static func make(
        book: LibraryBookRecord?,
        state: PlaybackState,
        chapterTitle: String?
    ) -> PlaybackBarPresentation? {
        guard let book else { return nil }

        let statusText: String?
        let canSeek: Bool
        switch state {
        case .bufferingForIndex:
            statusText = "Preparing the next passage…"
            canSeek = false
        case .seeking:
            statusText = "Seeking…"
            canSeek = false
        case let .failed(description):
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = trimmed.isEmpty ? "Playback unavailable" : trimmed
            canSeek = false
        case .stopped, .playing, .paused:
            statusText = nil
            canSeek = true
        }

        let trimmedAuthor = book.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = trimmedAuthor.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Author"
        return PlaybackBarPresentation(
            bookID: book.id,
            title: book.title,
            author: author,
            chapterTitle: chapterTitle,
            statusText: statusText,
            isPlaying: state == .playing,
            canSeek: canSeek
        )
    }
}

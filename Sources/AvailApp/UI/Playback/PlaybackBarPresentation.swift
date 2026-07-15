import Foundation

struct PlaybackBarPresentation: Equatable {
    let bookID: UUID
    let title: String
    let author: String
    let chapterTitle: String?
    let statusText: String?
    let isPlaying: Bool
    let canSeek: Bool
    let canTogglePlayback: Bool

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
        let canTogglePlayback: Bool
        switch state {
        case .bufferingForIndex:
            statusText = "Preparing the next passage…"
            canSeek = false
            canTogglePlayback = false
        case .seeking:
            statusText = "Seeking…"
            canSeek = false
            canTogglePlayback = false
        case let .failed(description):
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = trimmed.isEmpty ? "Playback unavailable" : trimmed
            canSeek = false
            canTogglePlayback = false
        case .stopped, .playing, .paused:
            statusText = nil
            canSeek = true
            canTogglePlayback = true
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
            canSeek: canSeek,
            canTogglePlayback: canTogglePlayback
        )
    }
}

struct LibraryPlaybackBarContext {
    let book: LibraryBookRecord
    let presentation: PlaybackBarPresentation

    static func make(
        books: [LibraryBookRecord],
        currentBookID: UUID?,
        state: PlaybackState,
        chapterTitle: String?
    ) -> LibraryPlaybackBarContext? {
        guard let currentBookID,
            let book = books.first(where: { $0.id == currentBookID }),
            let presentation = PlaybackBarPresentation.make(
                book: book,
                state: state,
                chapterTitle: chapterTitle
            )
        else { return nil }

        return LibraryPlaybackBarContext(book: book, presentation: presentation)
    }
}

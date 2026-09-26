import Foundation

enum PersistentPlayerToggleAction: Equatable {
    case pause
    case resume
    case play
    case none
}

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

    static func toggleAction(for state: PlaybackState) -> PersistentPlayerToggleAction {
        switch state {
        case .playing:
            .pause
        case .paused:
            .resume
        case .stopped, .failed:
            .play
        case .preparingVoice:
            .pause
        case .bufferingForIndex, .seeking:
            .none
        }
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
        case .preparingVoice:
            statusText = "Preparing voice audio…"
            canSeek = true
            canTogglePlayback = true
        case .seeking:
            statusText = "Seeking…"
            canSeek = false
            canTogglePlayback = false
        case let .failed(description):
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = trimmed.isEmpty ? "Playback unavailable" : trimmed
            canSeek = false
            canTogglePlayback = true
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

enum PersistentPlayerMode: Equatable {
    case empty
    case resumable(UUID)
    case active(UUID)
}

struct PersistentPlayerContext {
    let mode: PersistentPlayerMode
    let book: LibraryBookRecord?
    let presentation: PlaybackBarPresentation?

    static func make(
        books: [LibraryBookRecord],
        currentBookID: UUID?,
        state: PlaybackState,
        chapterTitle: String?
    ) -> PersistentPlayerContext {
        if let currentBookID,
            let activeBook = books.first(where: {
                $0.id == currentBookID && $0.state != .missing
            }),
            let presentation = PlaybackBarPresentation.make(
                book: activeBook,
                state: state,
                chapterTitle: chapterTitle
            )
        {
            return PersistentPlayerContext(
                mode: .active(activeBook.id),
                book: activeBook,
                presentation: presentation
            )
        }

        let resumableBook =
            books
            .filter {
                $0.state != .missing
                    && $0.state != .failed
                    && $0.isPlayable
                    && $0.positionUpdatedAt != nil
            }
            .max {
                ($0.positionUpdatedAt ?? .distantPast)
                    < ($1.positionUpdatedAt ?? .distantPast)
            }

        if let resumableBook,
            let presentation = PlaybackBarPresentation.make(
                book: resumableBook,
                state: .stopped,
                chapterTitle: nil
            )
        {
            return PersistentPlayerContext(
                mode: .resumable(resumableBook.id),
                book: resumableBook,
                presentation: presentation
            )
        }

        return PersistentPlayerContext(mode: .empty, book: nil, presentation: nil)
    }
}

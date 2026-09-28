import SwiftUI

struct FloatingPlaybackBar: View {
    let context: PersistentPlayerContext
    let artworkURL: URL?
    let currentWordOffset: Int
    let previousChapter: () -> Void
    let skipBackward: () -> Void
    let togglePlayback: () -> Void
    let skipForward: () -> Void
    let nextChapter: () -> Void
    let seek: (Int) -> Void
    let openZen: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if let book = context.book,
                let presentation = context.presentation
            {
                ViewThatFits(in: .horizontal) {
                    fullLayout(book: book, presentation: presentation)
                    compactLayout(book: book, presentation: presentation)
                }
            } else {
                emptyLayout
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("persistent-player")
    }

    private func fullLayout(
        book: LibraryBookRecord,
        presentation: PlaybackBarPresentation
    ) -> some View {
        HStack(spacing: 10) {
            metadata(book: book, presentation: presentation)
                .padding(11)
                .frame(width: 238, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))

            PlaybackTransportControls(
                isPlaying: presentation.isPlaying,
                controlsEnabled: advancedControlsEnabled && presentation.canSeek,
                toggleEnabled: toggleEnabled(presentation),
                inactiveLabel: isResumable ? "Resume" : "Play",
                previousChapter: previousChapter,
                skipBackward: skipBackward,
                togglePlayback: togglePlayback,
                skipForward: skipForward,
                nextChapter: nextChapter
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 16)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))

            HStack(spacing: 12) {
                PlaybackProgressControl(
                    currentWordOffset: currentWordOffset,
                    totalWordCount: book.indexedWordCount,
                    narrationRate: book.narrationRate,
                    canSeek: advancedControlsEnabled && presentation.canSeek,
                    seek: seek
                )
                .frame(minWidth: 210)

                Button("Open Zen", systemImage: "rectangle.split.2x1", action: openZen)
                    .buttonStyle(.glass)
                    .help("Open the focused listening and reading window")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .frame(minWidth: 790)
        .accessibilityIdentifier("full-player-layout")
    }

    private func compactLayout(
        book: LibraryBookRecord,
        presentation: PlaybackBarPresentation
    ) -> some View {
        HStack(spacing: 12) {
            BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 7)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(compactDetail(presentation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlaybackToggleButton(
                isPlaying: presentation.isPlaying,
                isEnabled: toggleEnabled(presentation),
                inactiveLabel: isResumable ? "Resume" : "Play",
                action: togglePlayback
            )

            Button(action: openZen) {
                Image(systemName: "rectangle.split.2x1")
                    .frame(width: 18, height: 18)
            }
            .buttonBorderShape(.circle)
            .buttonStyle(.glass)
            .accessibilityLabel("Open Zen")
            .help("Open the focused listening and reading window")
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityIdentifier("compact-player-layout")
    }

    private var emptyLayout: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose a book to listen")
                    .font(.headline)
                Text("Your player stays here while you browse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PlaybackToggleButton(
                isPlaying: false,
                isEnabled: false,
                action: {}
            )
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func metadata(
        book: LibraryBookRecord,
        presentation: PlaybackBarPresentation
    ) -> some View {
        HStack(spacing: 11) {
            BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 7)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(presentation.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(compactDetail(presentation))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var advancedControlsEnabled: Bool {
        if case .active = context.mode { true } else { false }
    }

    private var isResumable: Bool {
        if case .resumable = context.mode { true } else { false }
    }

    private func toggleEnabled(_ presentation: PlaybackBarPresentation) -> Bool {
        switch context.mode {
        case .empty:
            false
        case .resumable:
            presentation.canTogglePlayback
        case .active:
            presentation.canTogglePlayback
        }
    }

    private func compactDetail(_ presentation: PlaybackBarPresentation) -> String {
        if isResumable { return "Ready to resume" }
        return presentation.statusText ?? presentation.chapterTitle ?? presentation.author
    }

    private var accessibilityLabel: String {
        if let title = context.presentation?.title { return "Player, \(title)" }
        return "Player, choose a book to listen"
    }
}

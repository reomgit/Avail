import SwiftUI

struct FloatingPlaybackBar: View {
    let book: LibraryBookRecord
    let presentation: PlaybackBarPresentation
    let artworkURL: URL?
    let currentWordOffset: Int
    let totalWordCount: Int
    let narrationRate: Double
    let previousChapter: () -> Void
    let skipBackward: () -> Void
    let togglePlayback: () -> Void
    let skipForward: () -> Void
    let nextChapter: () -> Void
    let seek: (Int) -> Void
    let openZen: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullLayout
            compactLayout
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(presentation.title)")
    }

    private var fullLayout: some View {
        AdaptiveGlassContainer(spacing: 8) {
            HStack(spacing: 8) {
                AdaptiveGlassSurface {
                    metadata
                        .padding(10)
                }

                AdaptiveGlassSurface {
                    PlaybackTransportControls(
                        isPlaying: presentation.isPlaying,
                        controlsEnabled: presentation.canSeek,
                        toggleEnabled: presentation.canTogglePlayback,
                        previousChapter: previousChapter,
                        skipBackward: skipBackward,
                        togglePlayback: togglePlayback,
                        skipForward: skipForward,
                        nextChapter: nextChapter
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 15)
                }

                AdaptiveGlassSurface {
                    HStack(spacing: 12) {
                        PlaybackProgressControl(
                            currentWordOffset: currentWordOffset,
                            totalWordCount: totalWordCount,
                            narrationRate: narrationRate,
                            canSeek: presentation.canSeek,
                            seek: seek
                        )
                        .frame(minWidth: 210)

                        Button("Open Zen", systemImage: "rectangle.split.2x1", action: openZen)
                            .adaptiveGlassButtonStyle()
                            .help("Open the focused listening and reading window")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(minWidth: 790)
    }

    private var compactLayout: some View {
        AdaptiveGlassContainer(spacing: 8) {
            AdaptiveGlassSurface {
                HStack(spacing: 12) {
                    BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 8)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(compactDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlaybackToggleButton(
                        isPlaying: presentation.isPlaying,
                        isEnabled: presentation.canTogglePlayback,
                        action: togglePlayback
                    )

                    Button(action: openZen) {
                        Image(systemName: "rectangle.split.2x1")
                            .frame(width: 18, height: 18)
                    }
                    .buttonBorderShape(.circle)
                    .adaptiveGlassButtonStyle()
                    .accessibilityLabel("Open Zen")
                    .help("Open the focused listening and reading window")
                }
                .padding(10)
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 11) {
            BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 8)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(presentation.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detail = presentation.statusText ?? presentation.chapterTitle {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 175, alignment: .leading)
        }
    }

    private var compactDetail: String {
        presentation.statusText ?? presentation.chapterTitle ?? presentation.author
    }
}

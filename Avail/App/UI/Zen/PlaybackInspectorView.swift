import SwiftUI

struct PlaybackInspectorView: View {
    let model: ZenViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                cover

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.book?.title ?? "Book")
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                    Text(model.book?.author ?? "Unknown Author")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                ChapterMenu(model: model)
                transportControls
                progressControls
                VoiceAndRateControls(model: model)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let book = model.book {
            BookArtworkView(book: book, artworkURL: model.artworkURL, cornerRadius: 10)
                .frame(maxWidth: 170)
                .frame(maxWidth: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private var transportControls: some View {
        GlassEffectContainer(spacing: 8) {
            PlaybackTransportControls(
                isPlaying: model.playbackControlState.isPlaying,
                controlsEnabled: model.isConnectedToActivePlayback && (model.playbackPresentation?.canSeek ?? false),
                toggleEnabled: model.playbackControlState.canTogglePlayback,
                previousChapter: { Task { await model.playback.previousChapter() } },
                skipBackward: { Task { await model.playback.seek(by: -15) } },
                togglePlayback: model.togglePlayback,
                skipForward: { Task { await model.playback.seek(by: 15) } },
                nextChapter: { Task { await model.playback.nextChapter() } }
            )
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity)
    }

    private var progressControls: some View {
        PlaybackProgressControl(
            currentWordOffset: model.playback.currentNormalizedWordOffset,
            totalWordCount: model.book?.indexedWordCount ?? 0,
            narrationRate: model.book?.narrationRate ?? 1,
            canSeek: model.isConnectedToActivePlayback && (model.playbackPresentation?.canSeek ?? false),
            seek: model.seek
        )
    }
}

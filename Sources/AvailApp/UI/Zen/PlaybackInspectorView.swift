import SwiftUI

struct PlaybackInspectorView: View {
    let model: ZenViewModel
    @State private var scrubValue = 0.0
    @State private var isScrubbing = false

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
        .background(.regularMaterial)
        .onAppear { scrubValue = Double(model.playback.currentNormalizedWordOffset) }
        .onChange(of: model.playback.currentNormalizedWordOffset) { _, newValue in
            if !isScrubbing { scrubValue = Double(newValue) }
        }
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: 170)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Book cover")
    }

    private var transportControls: some View {
        HStack(spacing: 12) {
            controlButton("Previous Chapter", systemImage: "backward.end.fill") {
                Task { await model.playback.previousChapter() }
            }
            controlButton("Back 15 Seconds", systemImage: "gobackward.15") {
                Task { await model.playback.seek(by: -15) }
            }
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.playback.state == .playing ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.circle)
            .accessibilityLabel(model.playback.state == .playing ? "Pause" : "Play")

            controlButton("Forward 15 Seconds", systemImage: "goforward.15") {
                Task { await model.playback.seek(by: 15) }
            }
            controlButton("Next Chapter", systemImage: "forward.end.fill") {
                Task { await model.playback.nextChapter() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(
                value: $scrubValue,
                in: 0...Double(max(1, model.book?.indexedWordCount ?? 1)),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { model.seek(to: Int(scrubValue)) }
                }
            )
            .accessibilityLabel("Book position")
            .accessibilityValue(progressAccessibilityValue)

            HStack {
                Text(elapsedTime, format: .time(pattern: .minuteSecond))
                Spacer()
                Text(remainingTime, format: .time(pattern: .minuteSecond))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var wordsPerSecond: Double {
        2.5 * max(0.5, min(model.book?.narrationRate ?? 1, 2))
    }

    private var elapsedTime: Duration {
        .seconds(scrubValue / wordsPerSecond)
    }

    private var remainingTime: Duration {
        let remainingWords = max(0, Double(model.book?.indexedWordCount ?? 0) - scrubValue)
        return .seconds(remainingWords / wordsPerSecond)
    }

    private var progressAccessibilityValue: String {
        let total = max(1, model.book?.indexedWordCount ?? 1)
        return ((scrubValue / Double(total)) * 100).formatted(.number.precision(.fractionLength(0))) + " percent"
    }

    private func controlButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}

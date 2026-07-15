import Observation
import SwiftUI

@MainActor
@Observable
final class PlaybackProgressModel {
    var value = 0.0
    private(set) var isScrubbing = false

    func synchronize(to wordOffset: Int) {
        guard !isScrubbing else { return }
        value = Double(max(0, wordOffset))
    }

    func editingChanged(_ editing: Bool) -> Int? {
        if editing {
            isScrubbing = true
            return nil
        }
        guard isScrubbing else { return nil }
        isScrubbing = false
        return max(0, Int(value.rounded()))
    }
}

struct PlaybackProgressControl: View {
    let currentWordOffset: Int
    let totalWordCount: Int
    let narrationRate: Double
    let canSeek: Bool
    let seek: (Int) -> Void

    @State private var model = PlaybackProgressModel()

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 5) {
            Slider(
                value: $model.value,
                in: 0...Double(max(1, totalWordCount)),
                onEditingChanged: { editing in
                    if let target = model.editingChanged(editing) {
                        seek(min(target, max(0, totalWordCount)))
                    }
                }
            )
            .disabled(!canSeek)
            .accessibilityLabel("Book position")
            .accessibilityValue(progressAccessibilityValue)

            HStack {
                Text(elapsedTime, format: .time(pattern: .minuteSecond))
                Spacer()
                Text(remainingTime, format: .time(pattern: .minuteSecond))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .onAppear { synchronize() }
        .onChange(of: currentWordOffset) { synchronize() }
        .onChange(of: totalWordCount) { synchronize() }
    }

    private var wordsPerSecond: Double {
        2.5 * max(0.5, min(narrationRate, 2))
    }

    private var elapsedTime: Duration {
        .seconds(model.value / wordsPerSecond)
    }

    private var remainingTime: Duration {
        let remainingWords = max(0, Double(totalWordCount) - model.value)
        return .seconds(remainingWords / wordsPerSecond)
    }

    private var progressAccessibilityValue: String {
        let total = max(1, totalWordCount)
        let percentage = (model.value / Double(total)) * 100
        return percentage.formatted(.number.precision(.fractionLength(0))) + " percent"
    }

    private func synchronize() {
        model.synchronize(to: min(currentWordOffset, max(0, totalWordCount)))
    }
}

import SwiftUI

struct PlaybackTransportControls: View {
    let isPlaying: Bool
    let controlsEnabled: Bool
    let previousChapter: () -> Void
    let skipBackward: () -> Void
    let togglePlayback: () -> Void
    let skipForward: () -> Void
    let nextChapter: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            secondaryButton(
                "Previous Chapter",
                systemImage: "backward.end.fill",
                action: previousChapter
            )
            secondaryButton(
                "Back 15 Seconds",
                systemImage: "gobackward.15",
                action: skipBackward
            )
            PlaybackToggleButton(isPlaying: isPlaying, action: togglePlayback)
            secondaryButton(
                "Forward 15 Seconds",
                systemImage: "goforward.15",
                action: skipForward
            )
            secondaryButton(
                "Next Chapter",
                systemImage: "forward.end.fill",
                action: nextChapter
            )
        }
        .disabled(!controlsEnabled)
    }

    private func secondaryButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonBorderShape(.circle)
        .adaptiveGlassButtonStyle()
        .accessibilityLabel(label)
        .help(label)
    }
}

struct PlaybackToggleButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 24, height: 24)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .adaptiveProminentButtonStyle()
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .help(isPlaying ? "Pause" : "Play")
    }
}

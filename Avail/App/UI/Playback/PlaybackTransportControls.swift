import SwiftUI

struct PlaybackTransportControls: View {
    let isPlaying: Bool
    let controlsEnabled: Bool
    let toggleEnabled: Bool
    let inactiveLabel: String
    let previousChapter: () -> Void
    let skipBackward: () -> Void
    let togglePlayback: () -> Void
    let skipForward: () -> Void
    let nextChapter: () -> Void

    init(
        isPlaying: Bool,
        controlsEnabled: Bool,
        toggleEnabled: Bool = true,
        inactiveLabel: String = "Play",
        previousChapter: @escaping () -> Void,
        skipBackward: @escaping () -> Void,
        togglePlayback: @escaping () -> Void,
        skipForward: @escaping () -> Void,
        nextChapter: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.controlsEnabled = controlsEnabled
        self.toggleEnabled = toggleEnabled
        self.inactiveLabel = inactiveLabel
        self.previousChapter = previousChapter
        self.skipBackward = skipBackward
        self.togglePlayback = togglePlayback
        self.skipForward = skipForward
        self.nextChapter = nextChapter
    }

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
            PlaybackToggleButton(
                isPlaying: isPlaying,
                isEnabled: toggleEnabled,
                inactiveLabel: inactiveLabel,
                action: togglePlayback
            )
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
        .buttonStyle(.glass)
        .disabled(!controlsEnabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct PlaybackToggleButton: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let inactiveLabel: String
    let action: () -> Void

    init(
        isPlaying: Bool,
        isEnabled: Bool = true,
        inactiveLabel: String = "Play",
        action: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.isEnabled = isEnabled
        self.inactiveLabel = inactiveLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 24, height: 24)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
        .disabled(!isEnabled)
        .accessibilityLabel(isPlaying ? "Pause" : inactiveLabel)
        .help(isPlaying ? "Pause" : inactiveLabel)
    }
}

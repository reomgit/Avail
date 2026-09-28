import SwiftUI

struct NarrationActivityStrip: View {
    @Environment(AppEnvironment.self) private var environment

    private var presentation: NarrationActivityPresentation? {
        NarrationActivityPresentation.make(
            state: environment.playbackCoordinator?.state,
            isPreviewPreparing: environment.isPreparingVoicePreview
        )
    }

    var body: some View {
        if let presentation {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .accessibilityLabel(presentation.label)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.label)
            .accessibilityIdentifier("narration-activity-progress")
        }
    }
}

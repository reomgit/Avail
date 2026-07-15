import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch environment.launchState {
            case .needsLibraryLocation:
                LibraryLocationView()
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to your library…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .ready:
                LibraryRootView()
            case let .failed(message):
                LibraryLocationView(
                    title: "Reconnect Your Library",
                    description: message
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ContentUnavailableView(
            "Choose a Library Folder",
            systemImage: "books.vertical",
            description: Text("Avail keeps your books in a folder you control.")
        )
        .accessibilityHint(environment.launchState == .needsLibraryLocation ? "Select a folder to begin." : "")
        .frame(minWidth: 720, minHeight: 480)
    }
}

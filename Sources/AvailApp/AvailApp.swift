import SwiftUI

@main
struct AvailApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("Avail") {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
        }
        .commands {
            LibraryCommands()
            ToolbarCommands()
        }

        Settings {
            SettingsRootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
        }
    }
}

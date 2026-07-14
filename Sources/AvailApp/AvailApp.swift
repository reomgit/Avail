import SwiftUI

@main
struct AvailApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup("Avail") {
            RootView()
                .environment(environment)
        }

        Settings {
            SettingsRootView()
                .environment(environment)
        }
    }
}

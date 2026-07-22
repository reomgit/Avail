import AppKit
import SwiftUI

@main
struct AvailApp: App {
    @State private var environment: AppEnvironment

    init() {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITesting") {
                _environment = State(initialValue: AppEnvironment.uiTestingFixture())
                DispatchQueue.main.async {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                return
            }
        #endif
        _environment = State(initialValue: AppEnvironment())
    }

    var body: some Scene {
        WindowGroup("Avail") {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
                .task {
                    #if DEBUG
                        await environment.prepareUITestingFixtureIfNeeded()
                    #endif
                }
        }
        .defaultSize(
            width: ProcessInfo.processInfo.arguments.contains("-UITestCompact") ? 720 : 1_100,
            height: 720
        )
        .commands {
            LibraryCommands()
            ToolbarCommands()
        }

        WindowGroup("Zen", id: "zen", for: UUID.self) { $bookID in
            if let bookID {
                ZenReaderView(bookID: bookID)
                    .environment(environment)
                    .modelContainer(environment.modelContainer)
            } else {
                ContentUnavailableView("Book Unavailable", systemImage: "book.closed")
            }
        }
        .defaultSize(width: 1_080, height: 720)

        Settings {
            SettingsRootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
        }
    }
}

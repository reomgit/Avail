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

import SwiftUI

struct LibraryCommandActions {
    var importBooks: () -> Void
    var togglePlayback: () -> Void
    var openZen: () -> Void
    var canPlay: Bool
    var canOpenZen: Bool
}

private struct LibraryCommandActionsKey: FocusedValueKey {
    typealias Value = LibraryCommandActions
}

extension FocusedValues {
    var libraryCommandActions: LibraryCommandActions? {
        get { self[LibraryCommandActionsKey.self] }
        set { self[LibraryCommandActionsKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Books…") { actions?.importBooks() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("Listen") {
            Button("Play or Pause") { actions?.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(actions?.canPlay != true)
            Button("Open Zen") { actions?.openZen() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(actions?.canOpenZen != true)
        }
    }
}

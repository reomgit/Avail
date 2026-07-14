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
    @FocusedValue(\.zenCommandActions) private var zenActions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Books…") { actions?.importBooks() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("Listen") {
            Button("Play or Pause") {
                if let zenActions { zenActions.togglePlayback() } else { actions?.togglePlayback() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(zenActions == nil && actions?.canPlay != true)
            Button("Open Zen") { actions?.openZen() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(actions?.canOpenZen != true)
            Divider()
            Button("Skip Back 15 Seconds") { zenActions?.seekBackward() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(zenActions == nil)
            Button("Skip Forward 15 Seconds") { zenActions?.seekForward() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(zenActions == nil)
            Button("Previous Chapter") { zenActions?.previousChapter() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(zenActions == nil)
            Button("Next Chapter") { zenActions?.nextChapter() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(zenActions == nil)
        }
    }
}

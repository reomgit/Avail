import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let playbackSymbol: String
    let canPlay: Bool
    let canOpenZen: Bool
    let importBooks: () -> Void
    let togglePlayback: () -> Void
    let openZen: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                importButton
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .primaryAction) {
                playbackButtons
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                importButton
                playbackButtons
            }
        }
    }

    private var importButton: some View {
        Button("Import", systemImage: "plus", action: importBooks)
            .help("Import EPUB or PDF books")
    }

    @ViewBuilder
    private var playbackButtons: some View {
        Button("Listen", systemImage: playbackSymbol, action: togglePlayback)
            .disabled(!canPlay)
            .help("Play or pause the selected book")
        Button("Open Zen", systemImage: "rectangle.split.2x1", action: openZen)
            .disabled(!canOpenZen)
            .help("Open the focused listening and reading window")
    }
}

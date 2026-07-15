import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let importBooks: () -> Void
    let refreshLibrary: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Import", systemImage: "plus", action: importBooks)
                .help("Import EPUB or PDF books")
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Refresh Library", systemImage: "arrow.clockwise", action: refreshLibrary)
                .help("Scan the selected library folder again")
        }
    }
}

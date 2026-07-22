import SwiftUI
import UniformTypeIdentifiers

struct LibraryLocationView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isChoosingFolder = false
    var title = "Choose a Library Folder"
    var description = "Avail keeps imported EPUB and PDF books in a folder you control. Documents/Avail is a good choice, but no folder is created until you confirm it."

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "books.vertical")
        } description: {
            Text(description)
        } actions: {
            Button("Choose Folder…") {
                isChoosingFolder = true
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await environment.selectLibraryLocation(url) }
        }
        .accessibilityHint("Choose an existing folder or create one in the system dialog.")
    }
}

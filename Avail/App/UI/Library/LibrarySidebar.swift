import SwiftUI

struct LibrarySidebar: View {
    @Binding var selection: LibraryCollection
    let bookCount: Int
    let preparingCount: Int
    let hasContinueListening: Bool

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                sidebarRow("All Books", systemImage: "books.vertical", detail: "\(bookCount) books")
                    .tag(LibraryCollection.allBooks)
                sidebarRow(
                    "Continue Listening",
                    systemImage: "play.circle",
                    detail: hasContinueListening ? "Resume your latest book" : "No recent book"
                )
                .tag(LibraryCollection.continueListening)
                sidebarRow("Preparing", systemImage: "text.magnifyingglass", detail: "\(preparingCount) books")
                    .tag(LibraryCollection.preparing)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Avail")
    }

    private func sidebarRow(_ title: String, systemImage: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

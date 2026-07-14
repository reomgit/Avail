import SwiftUI

struct BookStateLabel: View {
    let book: LibraryBookRecord

    var body: some View {
        let presentation = BookStatePresentation(state: book.state)
        HStack(spacing: 5) {
            if book.state == .copying || book.state == .indexing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: presentation.systemImage)
            }
            Text(presentation.label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Book status")
        .accessibilityValue(presentation.accessibilityValue)
    }
}

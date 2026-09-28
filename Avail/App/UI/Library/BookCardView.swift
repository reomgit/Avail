import SwiftUI

struct BookCardView: View {
    let book: LibraryBookRecord
    let artworkURL: URL?
    let isPlayable: Bool
    let canOpenZen: Bool
    let openBook: () -> Void
    let play: () -> Void
    let openZen: () -> Void

    var body: some View {
        Button(action: openBook) {
            VStack(alignment: .leading, spacing: 10) {
                BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 8)
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(book.author ?? "Unknown Author")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    BookStateLabel(book: book)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Listen", systemImage: "play.fill", action: play)
                .disabled(!isPlayable)
            Button("Open Zen", systemImage: "rectangle.split.2x1", action: openZen)
                .disabled(!canOpenZen)
        }
        .accessibilityLabel(book.title)
        .accessibilityValue("\(book.author ?? "Unknown author"), \(BookStatePresentation(state: book.state).accessibilityValue)")
        .accessibilityHint("Open book details. Use the context menu to listen or open Zen.")
    }
}

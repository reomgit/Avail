import SwiftUI

struct BookCardView: View {
    let book: LibraryBookRecord
    let isSelected: Bool
    let isPlayable: Bool
    let select: () -> Void
    let play: () -> Void
    let openZen: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Image(systemName: book.format == .epub ? "book.closed" : "doc.richtext")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.tint, lineWidth: 3)
                        }
                    }

                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author ?? "Unknown Author")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                BookStateLabel(book: book)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Listen", systemImage: "play.fill", action: play)
                .disabled(!isPlayable)
            Button("Open Zen", systemImage: "rectangle.split.2x1", action: openZen)
                .disabled(!isPlayable)
        }
        .accessibilityLabel(book.title)
        .accessibilityValue("\(book.author ?? "Unknown author"), \(BookStatePresentation(state: book.state).accessibilityValue)")
        .accessibilityHint("Select this book. Use the context menu to listen or open Zen.")
    }
}

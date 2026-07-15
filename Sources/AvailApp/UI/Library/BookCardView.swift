import SwiftUI

struct BookCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let book: LibraryBookRecord
    let artworkURL: URL?
    let isSelected: Bool
    let isPlayable: Bool
    let select: () -> Void
    let play: () -> Void
    let openZen: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                BookArtworkView(book: book, artworkURL: artworkURL, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(book.author ?? "Unknown Author")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    BookStateLabel(book: book)
                        .padding(.top, 3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: isSelected ? 2 : 0)
            }
            .shadow(
                color: .black.opacity(isSelected ? 0.16 : 0.07),
                radius: isSelected ? 12 : 6,
                y: isSelected ? 6 : 3
            )
            .offset(y: isSelected ? -2 : 0)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
    }
}

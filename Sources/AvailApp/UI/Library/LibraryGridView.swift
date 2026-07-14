import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBookRecord]
    @Binding var selection: UUID?
    let canPlay: (LibraryBookRecord) -> Bool
    let play: (LibraryBookRecord) -> Void
    let openZen: (LibraryBookRecord) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 24)]

    var body: some View {
        if books.isEmpty {
            ContentUnavailableView(
                "No Books Here",
                systemImage: "books.vertical",
                description: Text("Import an EPUB or PDF, or choose a different collection.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                    ForEach(books) { book in
                        BookCardView(
                            book: book,
                            isSelected: selection == book.id,
                            isPlayable: canPlay(book),
                            select: { selection = book.id },
                            play: { if canPlay(book) { play(book) } },
                            openZen: { if canPlay(book) { openZen(book) } }
                        )
                    }
                }
                .padding(24)
            }
        }
    }
}

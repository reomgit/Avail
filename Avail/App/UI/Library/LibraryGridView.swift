import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBookRecord]
    let openBook: (LibraryBookRecord) -> Void
    let canPlay: (LibraryBookRecord) -> Bool
    let canOpenZen: (LibraryBookRecord) -> Bool
    let play: (LibraryBookRecord) -> Void
    let openZen: (LibraryBookRecord) -> Void
    let artworkURL: (LibraryBookRecord) -> URL?

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 26)]

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
                            artworkURL: artworkURL(book),
                            isPlayable: canPlay(book),
                            canOpenZen: canOpenZen(book),
                            openBook: { openBook(book) },
                            play: { if canPlay(book) { play(book) } },
                            openZen: { if canOpenZen(book) { openZen(book) } }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
    }
}

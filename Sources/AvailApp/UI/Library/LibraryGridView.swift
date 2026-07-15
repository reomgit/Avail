import SwiftUI

struct LibraryGridView: View {
    let books: [LibraryBookRecord]
    @Binding var selection: UUID?
    let canPlay: (LibraryBookRecord) -> Bool
    let play: (LibraryBookRecord) -> Void
    let openZen: (LibraryBookRecord) -> Void
    let bottomContentInset: CGFloat
    let artworkURL: (LibraryBookRecord) -> URL?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 218), spacing: 24)]

    init(
        books: [LibraryBookRecord],
        selection: Binding<UUID?>,
        canPlay: @escaping (LibraryBookRecord) -> Bool,
        play: @escaping (LibraryBookRecord) -> Void,
        openZen: @escaping (LibraryBookRecord) -> Void,
        bottomContentInset: CGFloat = 0,
        artworkURL: @escaping (LibraryBookRecord) -> URL? = { _ in nil }
    ) {
        self.books = books
        _selection = selection
        self.canPlay = canPlay
        self.play = play
        self.openZen = openZen
        self.bottomContentInset = bottomContentInset
        self.artworkURL = artworkURL
    }

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
                            isSelected: selection == book.id,
                            isPlayable: canPlay(book),
                            select: { selection = book.id },
                            play: { if canPlay(book) { play(book) } },
                            openZen: { if canPlay(book) { openZen(book) } }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24 + max(0, bottomContentInset))
            }
        }
    }
}

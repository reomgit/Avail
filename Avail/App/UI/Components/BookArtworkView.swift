import AppKit
import SwiftUI

struct BookArtworkSource {
    let image: NSImage?

    init(url: URL?) {
        image = url.flatMap { NSImage(contentsOf: $0) }
    }

    var usesPlaceholder: Bool { image == nil }
}

struct BookArtworkView: View {
    let book: LibraryBookRecord
    let artworkURL: URL?
    let cornerRadius: CGFloat

    init(
        book: LibraryBookRecord,
        artworkURL: URL?,
        cornerRadius: CGFloat = 12
    ) {
        self.book = book
        self.artworkURL = artworkURL
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack {
            placeholder

            if let image = source.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover for \(book.title)")
    }

    private var source: BookArtworkSource {
        BookArtworkSource(url: artworkURL)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [placeholderTint.opacity(0.24), Color(nsColor: .controlBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: book.format == .epub ? "book.closed.fill" : "doc.richtext.fill")
                    .font(.system(size: 36, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                Text(book.format.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(placeholderTint)
        }
    }

    private var placeholderTint: Color {
        book.format == .epub ? .accentColor : .secondary
    }
}

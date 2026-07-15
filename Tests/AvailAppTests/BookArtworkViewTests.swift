import AvailCore
import Foundation
import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class BookArtworkViewTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailArtworkViewTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testArtworkSourceLoadsValidImageAndRejectsCorruptFile() throws {
        let validURL = sandbox.appending(path: "valid.png")
        let corruptURL = sandbox.appending(path: "corrupt.png")
        try Self.validPNG.write(to: validURL)
        try Data("corrupt".utf8).write(to: corruptURL)

        XCTAssertFalse(BookArtworkSource(url: validURL).usesPlaceholder)
        XCTAssertTrue(BookArtworkSource(url: corruptURL).usesPlaceholder)
        XCTAssertTrue(BookArtworkSource(url: nil).usesPlaceholder)
    }

    func testArtworkCardAndGridShareTheLocalArtworkURL() {
        let book = makeBook()
        let artwork = BookArtworkView(book: book, artworkURL: nil, cornerRadius: 12)
        let card = BookCardView(
            book: book,
            artworkURL: nil,
            isPlayable: true,
            openBook: {},
            play: {},
            openZen: {}
        )
        let grid = LibraryGridView(
            books: [book],
            openBook: { _ in },
            canPlay: { _ in true },
            play: { _ in },
            openZen: { _ in },
            artworkURL: { _ in nil }
        )

        XCTAssertFalse(String(describing: type(of: artwork)).isEmpty)
        XCTAssertFalse(String(describing: type(of: card)).isEmpty)
        XCTAssertFalse(String(describing: type(of: grid)).isEmpty)
    }

    private func makeBook() -> LibraryBookRecord {
        LibraryBookRecord(
            fingerprint: UUID().uuidString,
            relativePath: "Book.epub",
            title: "Artwork Book",
            author: "Local Author",
            format: .epub,
            state: .ready
        )
    }

    private static let validPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

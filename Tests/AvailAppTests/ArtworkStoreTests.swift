import Foundation
import XCTest
@testable import AvailApp

final class ArtworkStoreTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!
    private var store: ArtworkStore!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailArtworkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = ArtworkStore(rootURL: sandbox)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testValidImageIsWrittenAndCanBeReadBack() async throws {
        let bookID = UUID()

        let relativePath = await store.persist(Self.validPNG, bookID: bookID)

        XCTAssertEqual(relativePath, "\(bookID.uuidString)/cover")
        let fileURL = try XCTUnwrap(store.fileURL(for: relativePath))
        XCTAssertEqual(try Data(contentsOf: fileURL), Self.validPNG)
    }

    func testInvalidImageIsNotPersisted() async {
        let bookID = UUID()

        let relativePath = await store.persist(Data("not an image".utf8), bookID: bookID)

        XCTAssertNil(relativePath)
    }

    func testInvalidReplacementPreservesExistingValidArtwork() async throws {
        let bookID = UUID()
        let originalPath = await store.persist(Self.validPNG, bookID: bookID)

        let replacementPath = await store.persist(Data("not an image".utf8), bookID: bookID)

        XCTAssertEqual(replacementPath, originalPath)
        let fileURL = try XCTUnwrap(store.fileURL(for: originalPath))
        XCTAssertEqual(try Data(contentsOf: fileURL), Self.validPNG)
    }

    func testRemoveDeletesPerBookArtworkDirectory() async throws {
        let bookID = UUID()
        let relativePath = await store.persist(Self.validPNG, bookID: bookID)
        let fileURL = try XCTUnwrap(store.fileURL(for: relativePath))

        await store.remove(bookID: bookID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    private static let validPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

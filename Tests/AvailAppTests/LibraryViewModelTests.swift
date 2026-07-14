import AvailCore
import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testFirstRunAndReconnectNeverEnableImportWithoutResolvedLibrary() {
        let model = LibraryViewModel()

        XCTAssertFalse(model.canImport(launchState: .needsLibraryLocation))
        XCTAssertFalse(model.canImport(launchState: .loading))
        XCTAssertFalse(model.canImport(launchState: .failed("Reconnect required")))
        XCTAssertTrue(model.canImport(launchState: .ready))
    }

    func testStatePresentationAlwaysCombinesLabelAndIcon() {
        let expected: [LibraryBookState: (String, String)] = [
            .copying: ("Copying", "doc.on.doc"),
            .indexing: ("Preparing", "text.magnifyingglass"),
            .ready: ("Ready", "checkmark.circle"),
            .playing: ("Listening", "waveform"),
            .missing: ("File Missing", "exclamationmark.triangle"),
            .failed: ("Needs Attention", "xmark.octagon"),
        ]

        for (state, value) in expected {
            let presentation = BookStatePresentation(state: state)
            XCTAssertEqual(presentation.label, value.0)
            XCTAssertEqual(presentation.systemImage, value.1)
            XCTAssertFalse(presentation.accessibilityValue.isEmpty)
        }
    }

    func testContinueListeningChoosesMostRecentlyUpdatedPosition() {
        let older = makeBook(title: "Older")
        older.positionUpdatedAt = Date(timeIntervalSince1970: 100)
        let newer = makeBook(title: "Newer")
        newer.positionUpdatedAt = Date(timeIntervalSince1970: 200)
        let untouched = makeBook(title: "Untouched")

        XCTAssertEqual(
            LibraryViewModel().continueListeningBookID(in: [older, untouched, newer]),
            newer.id
        )
    }

    func testPlayRequiresCommittedThresholdOrCompleteIndexAndReadableFile() {
        let book = makeBook(title: "Book")
        book.indexedWordCount = 449
        XCTAssertFalse(LibraryViewModel().canPlay(book))

        book.indexedWordCount = 450
        XCTAssertTrue(LibraryViewModel().canPlay(book))

        book.state = .missing
        XCTAssertFalse(LibraryViewModel().canPlay(book))

        book.state = .ready
        book.indexedWordCount = 0
        book.isIndexComplete = true
        XCTAssertTrue(LibraryViewModel().canPlay(book))
    }

    private func makeBook(title: String) -> LibraryBookRecord {
        LibraryBookRecord(
            fingerprint: UUID().uuidString,
            relativePath: "\(title).epub",
            title: title,
            format: .epub
        )
    }
}

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
        older.indexedWordCount = 1_000
        older.positionUpdatedAt = Date(timeIntervalSince1970: 100)
        let newer = makeBook(title: "Newer")
        newer.indexedWordCount = 1_000
        newer.positionUpdatedAt = Date(timeIntervalSince1970: 200)
        let untouched = makeBook(title: "Untouched")

        XCTAssertEqual(
            LibraryViewModel().continueListeningBookID(in: [older, untouched, newer]),
            newer.id
        )
    }

    func testContinueListeningSkipsMissingFailedAndUnplayableRecords() {
        let missing = makeBook(title: "Missing")
        missing.indexedWordCount = 1_000
        missing.positionUpdatedAt = Date(timeIntervalSince1970: 300)
        missing.state = .missing

        let failed = makeBook(title: "Failed")
        failed.indexedWordCount = 1_000
        failed.positionUpdatedAt = Date(timeIntervalSince1970: 250)
        failed.state = .failed

        let unplayable = makeBook(title: "Unplayable")
        unplayable.positionUpdatedAt = Date(timeIntervalSince1970: 200)

        let valid = makeBook(title: "Valid")
        valid.indexedWordCount = 1_000
        valid.positionUpdatedAt = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(
            LibraryViewModel().continueListeningBookID(
                in: [missing, failed, unplayable, valid]
            ),
            valid.id
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

    func testBookSelectionPushesADetailRouteAndSidebarSelectionReturnsToGrid() {
        let model = LibraryViewModel()
        let bookID = UUID()

        model.openBook(bookID)

        XCTAssertEqual(model.path, [.book(bookID)])
        XCTAssertEqual(model.selectedBookID, bookID)

        model.selectCollection(.preparing)

        XCTAssertEqual(model.collection, .preparing)
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertNil(model.selectedBookID)
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

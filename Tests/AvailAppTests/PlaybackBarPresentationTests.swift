import AvailCore
import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class PlaybackBarPresentationTests: XCTestCase {
    func testActiveBookKeepsPlayerVisibleAcrossSessionStates() {
        let states: [PlaybackState] = [
            .stopped,
            .playing,
            .paused,
            .bufferingForIndex,
            .seeking,
            .failed("Speech unavailable"),
        ]

        for state in states {
            XCTAssertNotNil(
                PlaybackBarPresentation.make(
                    book: makeBook(),
                    state: state,
                    chapterTitle: "Chapter 2"
                )
            )
        }
    }

    func testMissingBookHidesPlayer() {
        XCTAssertNil(
            PlaybackBarPresentation.make(
                book: nil,
                state: .playing,
                chapterTitle: "Chapter 2"
            )
        )
    }

    func testTransientAndFailureStatesMapToAccessibleStatus() throws {
        let buffering = try XCTUnwrap(makePresentation(state: .bufferingForIndex))
        let seeking = try XCTUnwrap(makePresentation(state: .seeking))
        let failed = try XCTUnwrap(makePresentation(state: .failed("Speech unavailable")))

        XCTAssertEqual(buffering.statusText, "Preparing the next passage…")
        XCTAssertFalse(buffering.canSeek)
        XCTAssertEqual(seeking.statusText, "Seeking…")
        XCTAssertFalse(seeking.canSeek)
        XCTAssertEqual(failed.statusText, "Speech unavailable")
        XCTAssertFalse(failed.canSeek)
    }

    func testPlayingAndPausedStatesMapPrimaryAction() throws {
        let playing = try XCTUnwrap(makePresentation(state: .playing))
        let paused = try XCTUnwrap(makePresentation(state: .paused))

        XCTAssertTrue(playing.isPlaying)
        XCTAssertEqual(playing.primaryActionLabel, "Pause")
        XCTAssertTrue(playing.canSeek)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.primaryActionLabel, "Play")
        XCTAssertTrue(paused.canSeek)
    }

    func testBookMetadataUsesAuthorFallbackAndPreservesChapter() throws {
        let presentation = try XCTUnwrap(makePresentation(state: .stopped, author: nil))

        XCTAssertEqual(presentation.title, "The Test Book")
        XCTAssertEqual(presentation.author, "Unknown Author")
        XCTAssertEqual(presentation.chapterTitle, "Chapter 2")
    }

    private func makePresentation(
        state: PlaybackState,
        author: String? = "Test Author"
    ) -> PlaybackBarPresentation? {
        PlaybackBarPresentation.make(
            book: makeBook(author: author),
            state: state,
            chapterTitle: "Chapter 2"
        )
    }

    private func makeBook(author: String? = "Test Author") -> LibraryBookRecord {
        LibraryBookRecord(
            fingerprint: UUID().uuidString,
            relativePath: "Book.epub",
            title: "The Test Book",
            author: author,
            format: .epub,
            state: .ready
        )
    }
}

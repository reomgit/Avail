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
        XCTAssertFalse(buffering.canTogglePlayback)
        XCTAssertEqual(seeking.statusText, "Seeking…")
        XCTAssertFalse(seeking.canSeek)
        XCTAssertFalse(seeking.canTogglePlayback)
        XCTAssertEqual(failed.statusText, "Speech unavailable")
        XCTAssertFalse(failed.canSeek)
        XCTAssertTrue(failed.canTogglePlayback)
    }

    func testPersistentPlayerRetriesWhenCurrentPlaybackHasFailed() {
        XCTAssertEqual(
            PlaybackBarPresentation.toggleAction(for: .failed("Voice is unavailable")),
            .play
        )
    }

    func testPlayingAndPausedStatesMapPrimaryAction() throws {
        let playing = try XCTUnwrap(makePresentation(state: .playing))
        let paused = try XCTUnwrap(makePresentation(state: .paused))

        XCTAssertTrue(playing.isPlaying)
        XCTAssertEqual(playing.primaryActionLabel, "Pause")
        XCTAssertTrue(playing.canSeek)
        XCTAssertTrue(playing.canTogglePlayback)
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.primaryActionLabel, "Play")
        XCTAssertTrue(paused.canSeek)
        XCTAssertTrue(paused.canTogglePlayback)
    }

    func testBookMetadataUsesAuthorFallbackAndPreservesChapter() throws {
        let presentation = try XCTUnwrap(makePresentation(state: .stopped, author: nil))

        XCTAssertEqual(presentation.title, "The Test Book")
        XCTAssertEqual(presentation.author, "Unknown Author")
        XCTAssertEqual(presentation.chapterTitle, "Chapter 2")
    }

    func testLibraryContextMatchesActiveRecordAndHidesStaleSession() throws {
        let book = makeBook()
        let context = try XCTUnwrap(
            LibraryPlaybackBarContext.make(
                books: [book],
                currentBookID: book.id,
                state: .paused,
                chapterTitle: "Chapter 2"
            )
        )

        XCTAssertTrue(context.book === book)
        XCTAssertEqual(context.presentation.bookID, book.id)
        XCTAssertNil(
            LibraryPlaybackBarContext.make(
                books: [book],
                currentBookID: UUID(),
                state: .paused,
                chapterTitle: nil
            )
        )
        XCTAssertNil(
            LibraryPlaybackBarContext.make(
                books: [book],
                currentBookID: nil,
                state: .stopped,
                chapterTitle: nil
            )
        )
    }

    func testPersistentPlayerUsesEmptyStateWithoutAnActiveOrResumableBook() {
        let unplayed = makeBook()
        unplayed.indexedWordCount = 1_000
        unplayed.isIndexComplete = true

        let context = PersistentPlayerContext.make(
            books: [unplayed],
            currentBookID: nil,
            state: .stopped,
            chapterTitle: nil
        )

        XCTAssertEqual(context.mode, .empty)
        XCTAssertNil(context.book)
        XCTAssertNil(context.presentation)
    }

    func testPersistentPlayerChoosesMostRecentlyPlayedValidBook() throws {
        let older = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 10))
        let newest = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 20))

        let context = PersistentPlayerContext.make(
            books: [newest, older],
            currentBookID: nil,
            state: .stopped,
            chapterTitle: nil
        )

        XCTAssertEqual(context.mode, .resumable(newest.id))
        XCTAssertTrue(context.book === newest)
        XCTAssertEqual(context.presentation?.primaryActionLabel, "Play")
    }

    func testPersistentPlayerActiveSessionWinsWhileBrowsingAndKeepsTransientStatus() throws {
        let active = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 10))
        let browsed = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 20))

        let context = PersistentPlayerContext.make(
            books: [active, browsed],
            currentBookID: active.id,
            state: .bufferingForIndex,
            chapterTitle: "Chapter 4"
        )

        XCTAssertEqual(context.mode, .active(active.id))
        XCTAssertTrue(context.book === active)
        XCTAssertEqual(context.presentation?.statusText, "Preparing the next passage…")
    }

    func testPersistentPlayerSkipsMissingAndStaleRecords() {
        let missing = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 30))
        missing.state = .missing
        let failed = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 25))
        failed.state = .failed
        let fallback = makeResumableBook(updatedAt: Date(timeIntervalSince1970: 20))

        let context = PersistentPlayerContext.make(
            books: [missing, failed, fallback],
            currentBookID: UUID(),
            state: .failed("Stale session"),
            chapterTitle: nil
        )

        XCTAssertEqual(context.mode, .resumable(fallback.id))
        XCTAssertTrue(context.book === fallback)
        XCTAssertNil(context.presentation?.statusText)
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

    private func makeResumableBook(updatedAt: Date) -> LibraryBookRecord {
        let book = makeBook()
        book.indexedWordCount = 1_000
        book.isIndexComplete = true
        book.normalizedWordOffset = 250
        book.positionUpdatedAt = updatedAt
        return book
    }
}

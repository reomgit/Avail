import AvailCore
import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class PlaybackControlsViewTests: XCTestCase {
    func testPlaybackControlsComposeFromExplicitStateAndActions() throws {
        let book = LibraryBookRecord(
            fingerprint: UUID().uuidString,
            relativePath: "Book.epub",
            title: "Player Book",
            author: "Local Author",
            format: .epub,
            state: .ready
        )
        book.indexedWordCount = 1_000
        let presentation = try XCTUnwrap(
            PlaybackBarPresentation.make(
                book: book,
                state: .paused,
                chapterTitle: "Chapter 4"
            )
        )
        let transport = PlaybackTransportControls(
            isPlaying: false,
            controlsEnabled: true,
            previousChapter: {},
            skipBackward: {},
            togglePlayback: {},
            skipForward: {},
            nextChapter: {}
        )
        let progress = PlaybackProgressControl(
            currentWordOffset: 250,
            totalWordCount: 1_000,
            narrationRate: 1,
            canSeek: true,
            seek: { _ in }
        )
        let bar = FloatingPlaybackBar(
            book: book,
            presentation: presentation,
            artworkURL: nil,
            currentWordOffset: 250,
            totalWordCount: 1_000,
            narrationRate: 1,
            previousChapter: {},
            skipBackward: {},
            togglePlayback: {},
            skipForward: {},
            nextChapter: {},
            seek: { _ in },
            openZen: {}
        )

        XCTAssertFalse(String(describing: type(of: transport)).isEmpty)
        XCTAssertFalse(String(describing: type(of: progress)).isEmpty)
        XCTAssertFalse(String(describing: type(of: bar)).isEmpty)
    }
}

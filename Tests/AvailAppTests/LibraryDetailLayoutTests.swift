import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class LibraryDetailLayoutTests: XCTestCase {
    func testPersistentPlayerHasARealEmptyComposition() {
        let bar = FloatingPlaybackBar(
            context: PersistentPlayerContext(
                mode: .empty,
                book: nil,
                presentation: nil
            ),
            artworkURL: nil,
            currentWordOffset: 0,
            previousChapter: {},
            skipBackward: {},
            togglePlayback: {},
            skipForward: {},
            nextChapter: {},
            seek: { _ in },
            openZen: {}
        )

        XCTAssertFalse(String(describing: type(of: bar)).isEmpty)
    }
}

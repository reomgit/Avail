import AppKit
import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class LibraryDetailLayoutTests: XCTestCase {
    func testDetailLayoutFillsProposedWindowSoPlayerRemainsVisible() throws {
        let renderer = ImageRenderer(
            content: LibraryDetailLayout {
                Color.clear.frame(width: 40, height: 40)
            } player: {
                Color.accentColor.frame(width: 80, height: 20)
            }
        )
        renderer.proposedSize = ProposedViewSize(width: 320, height: 240)

        let image = try XCTUnwrap(renderer.nsImage)

        XCTAssertEqual(image.size.width, 320, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 240, accuracy: 0.5)
    }
}

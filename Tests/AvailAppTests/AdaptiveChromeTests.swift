import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class AdaptiveChromeTests: XCTestCase {
    func testAdaptiveComponentsShareOneMacOS14CompatibleCallSite() {
        let container = AdaptiveGlassContainer(spacing: 12) {
            Text("Container")
        }
        let surface = AdaptiveGlassSurface(interactive: true) {
            Text("Surface")
                .padding()
        }
        let secondaryButton = Button("Secondary") {}
            .adaptiveGlassButtonStyle()
        let primaryButton = Button("Primary") {}
            .adaptiveProminentButtonStyle()
        let toolbar = LibraryToolbar(
            playbackSymbol: "play.fill",
            canPlay: true,
            canOpenZen: true,
            importBooks: {},
            togglePlayback: {},
            openZen: {}
        )

        XCTAssertFalse(String(describing: type(of: container)).isEmpty)
        XCTAssertFalse(String(describing: type(of: surface)).isEmpty)
        XCTAssertFalse(String(describing: type(of: secondaryButton)).isEmpty)
        XCTAssertFalse(String(describing: type(of: primaryButton)).isEmpty)
        XCTAssertFalse(String(describing: type(of: toolbar)).isEmpty)
    }
}

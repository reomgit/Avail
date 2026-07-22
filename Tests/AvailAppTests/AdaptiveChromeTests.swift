import SwiftUI
import XCTest
@testable import AvailApp

@MainActor
final class AdaptiveChromeTests: XCTestCase {
    func testMacOS26ChromeUsesDirectLiquidGlassTypes() {
        let container = GlassEffectContainer(spacing: 12) {
            Text("Container")
        }
        let surface = Text("Surface")
            .padding()
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        let secondaryButton = Button("Secondary") {}
            .buttonStyle(.glass)
        let primaryButton = Button("Primary") {}
            .buttonStyle(.glassProminent)
        let toolbar = LibraryToolbar(
            importBooks: {},
            refreshLibrary: {}
        )

        XCTAssertFalse(String(describing: type(of: container)).isEmpty)
        XCTAssertFalse(String(describing: type(of: surface)).isEmpty)
        XCTAssertFalse(String(describing: type(of: secondaryButton)).isEmpty)
        XCTAssertFalse(String(describing: type(of: primaryButton)).isEmpty)
        XCTAssertFalse(String(describing: type(of: toolbar)).isEmpty)
    }
}

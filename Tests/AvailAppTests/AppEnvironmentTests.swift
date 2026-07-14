import XCTest
@testable import AvailApp

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testFreshEnvironmentNeedsLibraryLocation() {
        let subject = AppEnvironment.bootstrapForTesting()

        XCTAssertNil(subject.selectedBookID)
        XCTAssertEqual(subject.launchState, .needsLibraryLocation)
    }
}

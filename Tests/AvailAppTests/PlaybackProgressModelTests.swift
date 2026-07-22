import XCTest
@testable import AvailApp

@MainActor
final class PlaybackProgressModelTests: XCTestCase {
    func testCoordinatorUpdatesSynchronizeWhileIdle() {
        let model = PlaybackProgressModel()

        model.synchronize(to: 120)

        XCTAssertEqual(model.value, 120)
        XCTAssertFalse(model.isScrubbing)
    }

    func testCoordinatorUpdatesAreIgnoredWhileScrubbing() {
        let model = PlaybackProgressModel()
        model.synchronize(to: 120)
        XCTAssertNil(model.editingChanged(true))
        model.value = 240

        model.synchronize(to: 300)

        XCTAssertEqual(model.value, 240)
        XCTAssertTrue(model.isScrubbing)
    }

    func testEndingScrubCommitsOneRoundedOffset() {
        let model = PlaybackProgressModel()
        XCTAssertNil(model.editingChanged(true))
        model.value = 240.6

        XCTAssertEqual(model.editingChanged(false), 241)
        XCTAssertNil(model.editingChanged(false))
        XCTAssertFalse(model.isScrubbing)
    }

    func testSynchronizationClampsNegativeOffsets() {
        let model = PlaybackProgressModel()

        model.synchronize(to: -20)

        XCTAssertEqual(model.value, 0)
    }
}

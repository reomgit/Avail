import Foundation
import XCTest
@testable import AvailPlayback

final class NeuralSynthesisQueueTests: XCTestCase {
    func testPreviewWaitsForActiveNarrationWithoutCancellingIt() async throws {
        let queue = NeuralSynthesisQueue()
        let recorder = QueueEventRecorder()
        let narration = Task {
            try await queue.run {
                await recorder.append("narration-started")
                try await Task.sleep(for: .milliseconds(80))
                await recorder.append("narration-finished")
                return "narration"
            }
        }

        let narrationStarted = await waitUntil { await recorder.contains("narration-started") }
        XCTAssertTrue(narrationStarted)
        let preview = Task {
            try await queue.run {
                await recorder.append("preview-started")
                return "preview"
            }
        }

        let narrationResult = try await narration.value
        let previewResult = try await preview.value
        XCTAssertEqual(narrationResult, "narration")
        XCTAssertEqual(previewResult, "preview")
        let events = await recorder.events
        XCTAssertEqual(events, ["narration-started", "narration-finished", "preview-started"])
    }

    func testCancellingObsoleteQueuedSynthesisDoesNotCancelTheNextRequest() async throws {
        let queue = NeuralSynthesisQueue()
        let recorder = QueueEventRecorder()
        let obsolete = Task {
            try await queue.run {
                await recorder.append("obsolete-started")
                try await Task.sleep(for: .seconds(30))
                return "obsolete"
            }
        }
        let obsoleteStarted = await waitUntil { await recorder.contains("obsolete-started") }
        XCTAssertTrue(obsoleteStarted)
        obsolete.cancel()
        do {
            _ = try await obsolete.value
            XCTFail("Expected the obsolete synthesis to be cancelled")
        } catch is CancellationError {
        }

        let current = try await queue.run {
            await recorder.append("current-started")
            return "current"
        }

        XCTAssertEqual(current, "current")
        let events = await recorder.events
        XCTAssertEqual(events, ["obsolete-started", "current-started"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else { return false }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }
}

private actor QueueEventRecorder {
    private(set) var events: [String] = []

    func append(_ event: String) { events.append(event) }
    func contains(_ event: String) -> Bool { events.contains(event) }
}

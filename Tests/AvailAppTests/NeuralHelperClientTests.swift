@testable import AvailApp
import Foundation
import XCTest

@MainActor
final class NeuralHelperClientTests: XCTestCase {
    func testRejectsEmptyPhraseBeforeOpeningHelper() async {
        let client = NeuralHelperClient()

        do {
            _ = try await client.synthesize(
                requestID: UUID(), bookmark: Data(), text: "  ")
            XCTFail("Expected empty phrase to be rejected")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Passage is empty.")
        }
    }
}

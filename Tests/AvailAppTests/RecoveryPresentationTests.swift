import XCTest
@testable import AvailApp

final class RecoveryPresentationTests: XCTestCase {
    func testEveryMVPFailureHasDistinctActionableCopy() {
        let issues: [RecoveryIssue] = [
            .bookmarkReconnect,
            .unsupportedType,
            .corruptEPUB,
            .protectedEPUB,
            .lockedPDF,
            .scannedPDF,
            .missingSource,
            .diskFull,
            .indexInterrupted,
            .frontierBuffering,
            .voiceUnavailable,
        ]
        let presentations = issues.map(RecoveryPresentation.init)

        XCTAssertEqual(Set(presentations.map(\.title)).count, issues.count)
        XCTAssertTrue(presentations.allSatisfy { !$0.explanation.isEmpty })
        XCTAssertTrue(presentations.allSatisfy { !$0.primaryButtonTitle.isEmpty })
        XCTAssertEqual(RecoveryPresentation(.bookmarkReconnect).action, .reconnectLibrary)
        XCTAssertEqual(RecoveryPresentation(.protectedEPUB).action, .chooseAnotherFile)
        XCTAssertEqual(RecoveryPresentation(.lockedPDF).action, .unlockPDFElsewhere)
        XCTAssertEqual(RecoveryPresentation(.scannedPDF).action, .chooseAnotherFile)
        XCTAssertEqual(RecoveryPresentation(.indexInterrupted).action, .retryIndex)
        XCTAssertEqual(RecoveryPresentation(.frontierBuffering).action, .waitForIndex)
        XCTAssertEqual(RecoveryPresentation(.voiceUnavailable).action, .chooseVoice)
    }

    func testDestructiveSourceRemovalAlwaysRequiresConfirmationAndUsesTrash() {
        let request = DestructiveRemovalRequest(bookID: UUID())

        XCTAssertTrue(request.requiresConfirmation)
        XCTAssertEqual(request.mode, .moveFileToTrash)
        XCTAssertEqual(RecoveryPresentation(.missingSource).action, .removeFromLibrary)
        XCTAssertTrue(RecoveryPresentation(.missingSource).isDestructive)
    }
}

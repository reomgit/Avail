import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testFreshEnvironmentNeedsLibraryLocation() {
        let subject = AppEnvironment.bootstrapForTesting()

        XCTAssertNil(subject.selectedBookID)
        XCTAssertEqual(subject.launchState, .needsLibraryLocation)
    }

    func testSelectingPopulatedLibraryStartsIndexingDiscoveredBook() async throws {
        let subject = AppEnvironment.bootstrapForTesting()
        let library = FileManager.default.temporaryDirectory
            .appending(path: "AvailEnvironmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("not-a-real-pdf".utf8).write(to: library.appending(path: "Existing.pdf"))

        await subject.selectLibraryLocation(library)

        let book = try XCTUnwrap(subject.libraryStore?.books().first)
        XCTAssertNotNil(subject.indexingCoordinator?.progress(for: book.id))
        await subject.indexingCoordinator?.waitUntilFinished(bookID: book.id)
    }
}

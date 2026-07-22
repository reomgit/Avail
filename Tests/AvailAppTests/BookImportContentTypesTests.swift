import UniformTypeIdentifiers
import XCTest
@testable import AvailApp

final class BookImportContentTypesTests: XCTestCase {
    func testAppleBooksEPUBPackageMatchesAllowedImportType() throws {
        let packageType = try XCTUnwrap(UTType("com.apple.ibooks.epub"))

        XCTAssertTrue(
            BookImportContentTypes.all.contains { packageType.conforms(to: $0) },
            "Unpacked EPUB packages should be enabled in the Import dialog"
        )
    }
}

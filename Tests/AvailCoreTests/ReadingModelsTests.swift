import XCTest
@testable import AvailCore

final class ReadingModelsTests: XCTestCase {
    func testReadingPositionPreservesExactGeneratedAudioFrame() throws {
        let audio = AudioResumePoint(
            clipKey: "voice-and-phrase-digest",
            phraseStartUTF16Offset: 32,
            phraseEndUTF16Offset: 74,
            frameOffset: 48_000,
            sampleRate: 24_000
        )
        let position = ReadingPosition(
            bookID: UUID(),
            sectionID: UUID(),
            chunkID: UUID(),
            utf16Offset: 32,
            normalizedWordOffset: 11,
            updatedAt: Date(timeIntervalSince1970: 1_234),
            audioResume: audio
        )

        let decoded = try JSONDecoder().decode(ReadingPosition.self, from: JSONEncoder().encode(position))

        XCTAssertEqual(decoded.audioResume, audio)
        XCTAssertEqual(decoded.audioResume?.frameOffset, 48_000)
    }

    func testLegacyReadingPositionDecodesWithoutAudioResume() throws {
        let legacy = """
            {"bookID":"00000000-0000-0000-0000-000000000001",\
            "sectionID":"00000000-0000-0000-0000-000000000002",\
            "chunkID":"00000000-0000-0000-0000-000000000003",\
            "utf16Offset":12,"normalizedWordOffset":44,"updatedAt":1234}
            """

        let decoded = try JSONDecoder().decode(ReadingPosition.self, from: Data(legacy.utf8))

        XCTAssertNil(decoded.audioResume)
    }

    func testReadingPositionRoundTripsThroughJSON() throws {
        let position = ReadingPosition(
            bookID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            chunkID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            utf16Offset: 12,
            normalizedWordOffset: 44,
            updatedAt: Date(timeIntervalSince1970: 1_234)
        )

        let data = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(ReadingPosition.self, from: data)

        XCTAssertEqual(decoded, position)
    }

    func testStableIdentifierIsDeterministicAndSensitiveToOrdinal() {
        let bookID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
        let locator = SourceLocator.epub(spineIndex: 2, href: "Text/chapter-2.xhtml")

        let first = StableIdentifier.make(bookID: bookID, kind: "chunk", locator: locator, ordinal: 3)
        let repeated = StableIdentifier.make(bookID: bookID, kind: "chunk", locator: locator, ordinal: 3)
        let next = StableIdentifier.make(bookID: bookID, kind: "chunk", locator: locator, ordinal: 4)

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, next)
    }

    func testIndexManifestRoundTripsWithFrontier() throws {
        let manifest = IndexManifest(
            schemaVersion: IndexManifest.currentSchemaVersion,
            batchFiles: ["batch-000000.json"],
            indexedWordCount: 500,
            playableFrontier: .pdf(pageIndex: 4),
            isComplete: false
        )

        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(IndexManifest.self, from: data), manifest)
    }
}

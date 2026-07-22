import XCTest
@testable import AvailCore

final class TextChunkerTests: XCTestCase {
    private let sectionID = UUID(uuidString: "20000000-0000-0000-0000-000000000000")!
    private let locator = SourceLocator.epub(spineIndex: 0, href: "chapter.xhtml")

    func testEmptyAndWhitespaceOnlyTextProducesNoChunks() {
        XCTAssertTrue(TextChunker().chunks(from: "", sectionID: sectionID, locator: locator).isEmpty)
        XCTAssertTrue(TextChunker().chunks(from: "  \n\n\t", sectionID: sectionID, locator: locator).isEmpty)
    }

    func testChunkingPreservesNormalizedContentAndOrdinals() {
        let sentence = "A thoughtful sentence carries enough meaning to be useful for a listener. "
        let input = String(repeating: sentence, count: 70)

        let chunks = TextChunker().chunks(from: input, sectionID: sectionID, locator: locator)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.map(\.ordinal), Array(chunks.indices))
        XCTAssertEqual(
            chunks.map(\.text).joined(separator: " ").normalizedWhitespace,
            input.normalizedWhitespace
        )
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 2_000 })
        XCTAssertTrue(chunks.dropLast().allSatisfy { $0.text.count >= 800 })
    }

    func testChunkIdentifiersAreStable() {
        let input = String(repeating: "Stable sentences make recovery deterministic. ", count: 50)
        let chunker = TextChunker()

        let first = chunker.chunks(from: input, sectionID: sectionID, locator: locator)
        let second = chunker.chunks(from: input, sectionID: sectionID, locator: locator)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testUnicodeEmojiAndCJKReceiveWordCountsAndUTF16Ranges() {
        let input = "Hello 👋🏽 reader. これは日本語の文章です。下一句继续阅读。"

        let chunks = TextChunker().chunks(from: input, sectionID: sectionID, locator: locator)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertGreaterThan(chunks[0].wordCount, 0)
        XCTAssertEqual(chunks[0].sourceRange.utf16Location, 0)
        XCTAssertEqual(chunks[0].sourceRange.utf16Length, input.normalizedForSpeech.utf16.count)
    }

    func testLongBreakableSentenceNeverExceedsHardLimitOrSplitsWords() {
        let word = "narration"
        let input = Array(repeating: word, count: 600).joined(separator: " ")

        let chunks = TextChunker().chunks(from: input, sectionID: sectionID, locator: locator)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 2_000 })
        XCTAssertTrue(
            chunks.allSatisfy { chunk in
                chunk.text.split(separator: " ").allSatisfy { $0 == Substring(word) }
            })
    }

    func testLongSentenceFollowedByAnotherSentenceDoesNotCreateReversedRange() {
        let longSentence = Array(repeating: "narration", count: 250).joined(separator: " ") + "."
        let input = longSentence + "\n\nA short sentence follows."

        let chunks = TextChunker().chunks(from: input, sectionID: sectionID, locator: locator)

        XCTAssertEqual(
            chunks.map(\.text).joined(separator: " ").normalizedWhitespace,
            input.normalizedWhitespace
        )
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 2_000 })
    }
}

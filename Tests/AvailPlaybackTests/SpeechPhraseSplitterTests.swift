import AvailCore
import XCTest
@testable import AvailPlayback

final class SpeechPhraseSplitterTests: XCTestCase {
    func testSplitsOnSentenceBoundaryAndKeepsUTF16Offsets() {
        let text = "👩🏽‍🚀 First sentence. Second sentence."
        let chunk = makeChunk(text)
        let splitter = SpeechPhraseSplitter(maximumCharacters: 24)

        let first = splitter.next(in: chunk, fromUTF16Offset: 0)
        let second = splitter.next(in: chunk, fromUTF16Offset: first!.range.location + first!.range.length)

        XCTAssertEqual(first?.text, "👩🏽‍🚀 First sentence.")
        XCTAssertEqual(second?.text, "Second sentence.")
        XCTAssertEqual(first?.range.location, 0)
        XCTAssertEqual(second?.range.location, ("👩🏽‍🚀 First sentence. " as NSString).length)
    }

    func testLongUnspacedPhraseIsBoundedWithoutSplittingGrapheme() {
        let chunk = makeChunk(String(repeating: "漢", count: 50))
        let splitter = SpeechPhraseSplitter(maximumCharacters: 20)

        let first = splitter.next(in: chunk, fromUTF16Offset: 0)
        let second = splitter.next(in: chunk, fromUTF16Offset: first!.range.location + first!.range.length)

        XCTAssertEqual(first?.text.count, 20)
        XCTAssertEqual(second?.range.location, 20)
    }

    private func makeChunk(_ text: String) -> SpeechChunk {
        SpeechChunk(
            id: UUID(), sectionID: UUID(), ordinal: 0, text: text, wordCount: 3,
            locator: .pdf(pageIndex: 0),
            sourceRange: SourceTextRange(utf16Location: 0, utf16Length: text.utf16.count)
        )
    }
}

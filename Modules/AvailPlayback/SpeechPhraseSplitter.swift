import AvailCore
import Foundation
import NaturalLanguage

public struct SpeechPhrase: Equatable, Sendable {
    public let text: String
    public let range: NSRange

    public init(text: String, range: NSRange) {
        self.text = text
        self.range = range
    }
}

public struct SpeechPhraseSplitter: Sendable {
    public let maximumCharacters: Int

    public init(maximumCharacters: Int = 300) {
        precondition(maximumCharacters > 0)
        self.maximumCharacters = maximumCharacters
    }

    public func next(in chunk: SpeechChunk, fromUTF16Offset requestedOffset: Int) -> SpeechPhrase? {
        let text = chunk.text
        let clamped = max(0, min(requestedOffset, text.utf16.count))
        var start = String.Index(utf16Offset: clamped, in: text)
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }
        guard start < text.endIndex else { return nil }

        let remainder = String(text[start...])
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = remainder
        var firstSentenceEnd: String.Index?
        tokenizer.enumerateTokens(in: remainder.startIndex..<remainder.endIndex) { range, _ in
            firstSentenceEnd = range.upperBound
            return false
        }
        let sentenceLength =
            firstSentenceEnd.map { remainder.distance(from: remainder.startIndex, to: $0) }
            ?? remainder.count
        let sentenceEnd = text.index(start, offsetBy: sentenceLength, limitedBy: text.endIndex) ?? text.endIndex
        var end = sentenceEnd
        if text.distance(from: start, to: end) > maximumCharacters {
            let limit = text.index(start, offsetBy: maximumCharacters)
            if let whitespace = text[start..<limit].lastIndex(where: \.isWhitespace), whitespace > start {
                end = whitespace
            } else {
                end = limit
            }
        }
        while end > start {
            let previous = text.index(before: end)
            guard text[previous].isWhitespace else { break }
            end = previous
        }
        guard end > start else { return nil }
        let range = NSRange(start..<end, in: text)
        return SpeechPhrase(text: String(text[start..<end]), range: range)
    }
}

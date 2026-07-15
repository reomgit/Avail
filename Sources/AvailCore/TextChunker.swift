import Foundation
import NaturalLanguage

public struct TextChunker: Sendable {
    public let targetMinimum: Int
    public let preferredMaximum: Int
    public let hardMaximum: Int

    public init(targetMinimum: Int = 800, preferredMaximum: Int = 1_200, hardMaximum: Int = 2_000) {
        precondition(targetMinimum > 0)
        precondition(preferredMaximum >= targetMinimum)
        precondition(hardMaximum >= preferredMaximum)
        self.targetMinimum = targetMinimum
        self.preferredMaximum = preferredMaximum
        self.hardMaximum = hardMaximum
    }

    public func chunks(from source: String, sectionID: UUID, locator: SourceLocator) -> [SpeechChunk] {
        let normalized = source.normalizedForSpeech
        guard !normalized.isEmpty else { return [] }

        let ranges = chunkRanges(in: normalized)
        return ranges.enumerated().map { ordinal, range in
            let text = String(normalized[range])
            let utf16Location = range.lowerBound.utf16Offset(in: normalized)
            let utf16Length = text.utf16.count
            return SpeechChunk(
                id: StableIdentifier.make(sectionID: sectionID, kind: "chunk", locator: locator, ordinal: ordinal),
                sectionID: sectionID,
                ordinal: ordinal,
                text: text,
                wordCount: wordCount(in: text),
                locator: locator,
                sourceRange: SourceTextRange(utf16Location: utf16Location, utf16Length: utf16Length)
            )
        }
    }

    private func chunkRanges(in text: String) -> [Range<String.Index>] {
        let fullRange = text.startIndex..<text.endIndex
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentenceEnds: [String.Index] = []
        tokenizer.enumerateTokens(in: fullRange) { range, _ in
            sentenceEnds.append(range.upperBound)
            return true
        }
        if sentenceEnds.last != text.endIndex {
            sentenceEnds.append(text.endIndex)
        }

        var result: [Range<String.Index>] = []
        var chunkStart = text.startIndex
        var previousEnd = text.startIndex

        for sentenceEnd in sentenceEnds {
            let candidate = trimmedRange(chunkStart..<sentenceEnd, in: text)
            let previous =
                previousEnd < chunkStart
                ? chunkStart..<chunkStart
                : trimmedRange(chunkStart..<previousEnd, in: text)

            if candidate.count(in: text) > preferredMaximum, previous.count(in: text) >= targetMinimum {
                result.append(previous)
                chunkStart = firstNonWhitespace(atOrAfter: previousEnd, in: text)
            }

            let updated = trimmedRange(chunkStart..<sentenceEnd, in: text)
            if updated.count(in: text) > hardMaximum {
                let split = hardSplit(updated, in: text)
                result.append(contentsOf: split)
                chunkStart = firstNonWhitespace(atOrAfter: sentenceEnd, in: text)
            }

            previousEnd = sentenceEnd
        }

        let remainder = trimmedRange(chunkStart..<text.endIndex, in: text)
        if !remainder.isEmpty {
            result.append(contentsOf: hardSplit(remainder, in: text))
        }
        return result.filter { !$0.isEmpty }
    }

    private func hardSplit(_ range: Range<String.Index>, in text: String) -> [Range<String.Index>] {
        guard range.count(in: text) > hardMaximum else { return [range] }

        var result: [Range<String.Index>] = []
        var start = range.lowerBound
        while text.distance(from: start, to: range.upperBound) > hardMaximum {
            let limit = text.index(start, offsetBy: hardMaximum)
            let prefix = text[start..<limit]
            if let whitespace = prefix.lastIndex(where: \Character.isWhitespace), whitespace > start {
                result.append(trimmedRange(start..<whitespace, in: text))
                start = firstNonWhitespace(atOrAfter: whitespace, in: text)
            } else if let whitespace = text[limit..<range.upperBound].firstIndex(where: \Character.isWhitespace) {
                result.append(trimmedRange(start..<whitespace, in: text))
                start = firstNonWhitespace(atOrAfter: whitespace, in: text)
            } else {
                result.append(start..<range.upperBound)
                return result
            }
        }

        let remainder = trimmedRange(start..<range.upperBound, in: text)
        if !remainder.isEmpty {
            result.append(remainder)
        }
        return result
    }

    private func wordCount(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func trimmedRange(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }
        while lower < upper {
            let previous = text.index(before: upper)
            guard text[previous].isWhitespace else { break }
            upper = previous
        }
        return lower..<upper
    }

    private func firstNonWhitespace(atOrAfter index: String.Index, in text: String) -> String.Index {
        var cursor = index
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        return cursor
    }
}

extension Range where Bound == String.Index {
    fileprivate func count(in text: String) -> Int {
        text.distance(from: lowerBound, to: upperBound)
    }
}

extension String {
    var normalizedForSpeech: String {
        let unixLines = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        var currentLines: [String] = []

        func appendParagraph() {
            guard !currentLines.isEmpty else { return }
            paragraphs.append(currentLines.joined(separator: " ").normalizedWhitespace)
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in unixLines.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                appendParagraph()
            } else {
                currentLines.append(trimmed)
            }
        }
        appendParagraph()
        return paragraphs.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var normalizedWhitespace: String {
        split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }
}

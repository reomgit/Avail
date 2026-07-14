import CryptoKit
import Foundation

public enum BookFormat: String, Codable, CaseIterable, Sendable {
    case epub
    case pdf
}

public enum SourceLocator: Codable, Hashable, Sendable {
    case epub(spineIndex: Int, href: String)
    case epubProgress(spineIndex: Int, href: String, nextChunkOrdinal: Int)
    case pdf(pageIndex: Int)
    case pdfProgress(pageIndex: Int, nextChunkOrdinal: Int)

    public var stableKey: String {
        switch self {
        case let .epub(spineIndex, href):
            "epub:\(spineIndex):\(href)"
        case let .epubProgress(spineIndex, href, nextChunkOrdinal):
            "epub-progress:\(spineIndex):\(href):\(nextChunkOrdinal)"
        case let .pdf(pageIndex):
            "pdf:\(pageIndex)"
        case let .pdfProgress(pageIndex, nextChunkOrdinal):
            "pdf-progress:\(pageIndex):\(nextChunkOrdinal)"
        }
    }
}

public struct SourceTextRange: Codable, Hashable, Sendable {
    public let utf16Location: Int
    public let utf16Length: Int

    public init(utf16Location: Int, utf16Length: Int) {
        self.utf16Location = utf16Location
        self.utf16Length = utf16Length
    }
}

public struct BookMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var authors: [String]
    public var languageCode: String?
    public var coverData: Data?

    public init(title: String, authors: [String] = [], languageCode: String? = nil, coverData: Data? = nil) {
        self.title = title
        self.authors = authors
        self.languageCode = languageCode
        self.coverData = coverData
    }
}

public struct ReadingSection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let title: String?
    public let locator: SourceLocator
    public let chunkIDs: [UUID]

    public init(id: UUID, ordinal: Int, title: String?, locator: SourceLocator, chunkIDs: [UUID]) {
        self.id = id
        self.ordinal = ordinal
        self.title = title
        self.locator = locator
        self.chunkIDs = chunkIDs
    }
}

public struct SpeechChunk: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sectionID: UUID
    public let ordinal: Int
    public let text: String
    public let wordCount: Int
    public let locator: SourceLocator
    public let sourceRange: SourceTextRange

    public init(
        id: UUID,
        sectionID: UUID,
        ordinal: Int,
        text: String,
        wordCount: Int,
        locator: SourceLocator,
        sourceRange: SourceTextRange
    ) {
        self.id = id
        self.sectionID = sectionID
        self.ordinal = ordinal
        self.text = text
        self.wordCount = wordCount
        self.locator = locator
        self.sourceRange = sourceRange
    }
}

public struct ReadingPosition: Codable, Equatable, Sendable {
    public let bookID: UUID
    public var sectionID: UUID
    public var chunkID: UUID
    public var utf16Offset: Int
    public var normalizedWordOffset: Int
    public var updatedAt: Date

    public init(
        bookID: UUID,
        sectionID: UUID,
        chunkID: UUID,
        utf16Offset: Int,
        normalizedWordOffset: Int,
        updatedAt: Date
    ) {
        self.bookID = bookID
        self.sectionID = sectionID
        self.chunkID = chunkID
        self.utf16Offset = utf16Offset
        self.normalizedWordOffset = normalizedWordOffset
        self.updatedAt = updatedAt
    }
}

public struct IndexBatch: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let sections: [ReadingSection]
    public let chunks: [SpeechChunk]
    public let resumeLocator: SourceLocator

    public init(ordinal: Int, sections: [ReadingSection], chunks: [SpeechChunk], resumeLocator: SourceLocator) {
        self.ordinal = ordinal
        self.sections = sections
        self.chunks = chunks
        self.resumeLocator = resumeLocator
    }
}

public struct IndexManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var batchFiles: [String]
    public var indexedWordCount: Int
    public var playableFrontier: SourceLocator?
    public var isComplete: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        batchFiles: [String] = [],
        indexedWordCount: Int = 0,
        playableFrontier: SourceLocator? = nil,
        isComplete: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.batchFiles = batchFiles
        self.indexedWordCount = indexedWordCount
        self.playableFrontier = playableFrontier
        self.isComplete = isComplete
    }
}

public enum IndexingPhase: String, Codable, Sendable {
    case waiting
    case readingMetadata
    case indexing
    case playable
    case complete
    case failed
}

public struct IndexingProgress: Codable, Equatable, Sendable {
    public var phase: IndexingPhase
    public var completedSourceUnits: Int
    public var totalSourceUnits: Int?
    public var indexedWordCount: Int
    public var playableFrontier: SourceLocator?
    public var errorDescription: String?

    public init(
        phase: IndexingPhase = .waiting,
        completedSourceUnits: Int = 0,
        totalSourceUnits: Int? = nil,
        indexedWordCount: Int = 0,
        playableFrontier: SourceLocator? = nil,
        errorDescription: String? = nil
    ) {
        self.phase = phase
        self.completedSourceUnits = completedSourceUnits
        self.totalSourceUnits = totalSourceUnits
        self.indexedWordCount = indexedWordCount
        self.playableFrontier = playableFrontier
        self.errorDescription = errorDescription
    }
}

public enum StableIdentifier {
    public static func make(bookID: UUID, kind: String, locator: SourceLocator, ordinal: Int) -> UUID {
        make(namespace: bookID.uuidString, kind: kind, locator: locator, ordinal: ordinal)
    }

    public static func make(sectionID: UUID, kind: String, locator: SourceLocator, ordinal: Int) -> UUID {
        make(namespace: sectionID.uuidString, kind: kind, locator: locator, ordinal: ordinal)
    }

    private static func make(namespace: String, kind: String, locator: SourceLocator, ordinal: Int) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)|\(kind)|\(locator.stableKey)|\(ordinal)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

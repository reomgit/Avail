import AvailCore
import Foundation
import SwiftData

enum LibraryBookState: String, Codable, CaseIterable {
    case copying
    case indexing
    case ready
    case playing
    case missing
    case failed
}

@Model
final class LibraryBookRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fingerprint: String
    var relativePath: String
    var title: String
    var author: String?
    var formatRawValue: String
    var stateRawValue: String
    var coverRelativePath: String?
    var languageCode: String?
    var fileResourceIdentifier: String?
    var fileSize: Int64
    var fileModificationDate: Date?
    var indexedWordCount: Int
    var isIndexComplete: Bool
    var currentSectionID: UUID?
    var currentChunkID: UUID?
    var utf16Offset: Int
    var normalizedWordOffset: Int
    var positionUpdatedAt: Date?
    var audioClipKey: String?
    var audioPhraseStartUTF16Offset: Int?
    var audioPhraseEndUTF16Offset: Int?
    var audioFrameOffset: Int64?
    var audioSampleRate: Int?
    var voiceIdentifier: String?
    var narrationRate: Double
    var lastErrorDescription: String?
    var createdAt: Date
    var updatedAt: Date

    var format: BookFormat {
        get { BookFormat(rawValue: formatRawValue) ?? .epub }
        set { formatRawValue = newValue.rawValue }
    }

    var state: LibraryBookState {
        get { LibraryBookState(rawValue: stateRawValue) ?? .failed }
        set { stateRawValue = newValue.rawValue }
    }

    var isPlayable: Bool {
        indexedWordCount >= 450 || isIndexComplete
    }

    init(
        id: UUID = UUID(),
        fingerprint: String,
        relativePath: String,
        title: String,
        author: String? = nil,
        format: BookFormat,
        state: LibraryBookState = .indexing,
        fileResourceIdentifier: String? = nil,
        fileSize: Int64 = 0,
        fileModificationDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.relativePath = relativePath
        self.title = title
        self.author = author
        self.formatRawValue = format.rawValue
        self.stateRawValue = state.rawValue
        self.fileResourceIdentifier = fileResourceIdentifier
        self.fileSize = fileSize
        self.fileModificationDate = fileModificationDate
        self.indexedWordCount = 0
        self.isIndexComplete = false
        self.utf16Offset = 0
        self.normalizedWordOffset = 0
        self.narrationRate = 1
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func update(position: ReadingPosition) {
        currentSectionID = position.sectionID
        currentChunkID = position.chunkID
        utf16Offset = position.utf16Offset
        normalizedWordOffset = position.normalizedWordOffset
        positionUpdatedAt = position.updatedAt
        audioClipKey = position.audioResume?.clipKey
        audioPhraseStartUTF16Offset = position.audioResume?.phraseStartUTF16Offset
        audioPhraseEndUTF16Offset = position.audioResume?.phraseEndUTF16Offset
        audioFrameOffset = position.audioResume?.frameOffset
        audioSampleRate = position.audioResume?.sampleRate
        updatedAt = position.updatedAt
    }

    func readingPosition() -> ReadingPosition? {
        guard let currentSectionID, let currentChunkID, let positionUpdatedAt else { return nil }
        return ReadingPosition(
            bookID: id,
            sectionID: currentSectionID,
            chunkID: currentChunkID,
            utf16Offset: utf16Offset,
            normalizedWordOffset: normalizedWordOffset,
            updatedAt: positionUpdatedAt,
            audioResume: audioResumePoint()
        )
    }

    private func audioResumePoint() -> AudioResumePoint? {
        guard let audioClipKey,
            let audioPhraseStartUTF16Offset,
            let audioPhraseEndUTF16Offset,
            let audioFrameOffset,
            let audioSampleRate,
            audioPhraseStartUTF16Offset >= 0,
            audioPhraseEndUTF16Offset >= audioPhraseStartUTF16Offset,
            audioFrameOffset >= 0,
            (8_000...192_000).contains(audioSampleRate)
        else { return nil }
        return AudioResumePoint(
            clipKey: audioClipKey,
            phraseStartUTF16Offset: audioPhraseStartUTF16Offset,
            phraseEndUTF16Offset: audioPhraseEndUTF16Offset,
            frameOffset: audioFrameOffset,
            sampleRate: audioSampleRate
        )
    }
}

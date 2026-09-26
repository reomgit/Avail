import AvailCore
import Foundation

public struct NarrationVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let languageCode: String

    public init(id: String, name: String, languageCode: String) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
    }

    public func matches(languageCode requestedLanguageCode: String) -> Bool {
        let voiceTag = Self.normalizedLanguageTag(languageCode)
        let requestedTag = Self.normalizedLanguageTag(requestedLanguageCode)
        guard !voiceTag.isEmpty, !requestedTag.isEmpty else { return false }
        if voiceTag == requestedTag { return true }
        return voiceTag.split(separator: "-").first == requestedTag.split(separator: "-").first
    }

    static func normalizedLanguageTag(_ languageCode: String) -> String {
        languageCode.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

public struct NarrationRequest: Hashable, Sendable {
    public let chunk: SpeechChunk
    public let voiceIdentifier: String?
    public let languageCode: String?
    public let rate: Float
    public let speedMultiplier: Float
    public let startUTF16Offset: Int
    public let audioResume: AudioResumePoint?

    public init(
        chunk: SpeechChunk,
        voiceIdentifier: String? = nil,
        languageCode: String? = nil,
        rate: Float = 0.5,
        speedMultiplier: Float = 1,
        startUTF16Offset: Int = 0,
        audioResume: AudioResumePoint? = nil
    ) {
        self.chunk = chunk
        self.voiceIdentifier = voiceIdentifier
        self.languageCode = languageCode
        self.rate = rate
        self.speedMultiplier = speedMultiplier
        self.startUTF16Offset = startUTF16Offset
        self.audioResume = audioResume
    }
}

public enum NarrationEvent: Equatable, Sendable {
    case voiceFallback(requestedIdentifier: String, selectedIdentifier: String?)
    case started(chunkID: UUID)
    case preparing(chunkID: UUID)
    case willSpeakRange(chunkID: UUID, range: NSRange)
    case audioPosition(chunkID: UUID, range: NSRange, resume: AudioResumePoint)
    case phraseFinished(chunkID: UUID, nextUTF16Offset: Int)
    case failed(chunkID: UUID, reason: String)
    case paused(chunkID: UUID)
    case resumed(chunkID: UUID)
    case finished(chunkID: UUID)
    case cancelled(chunkID: UUID)
}

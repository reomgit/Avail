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

    public init(
        chunk: SpeechChunk,
        voiceIdentifier: String? = nil,
        languageCode: String? = nil,
        rate: Float = 0.5
    ) {
        self.chunk = chunk
        self.voiceIdentifier = voiceIdentifier
        self.languageCode = languageCode
        self.rate = rate
    }
}

public enum NarrationEvent: Equatable, Sendable {
    case voiceFallback(requestedIdentifier: String, selectedIdentifier: String?)
    case started(chunkID: UUID)
    case willSpeakRange(chunkID: UUID, range: NSRange)
    case paused(chunkID: UUID)
    case resumed(chunkID: UUID)
    case finished(chunkID: UUID)
    case cancelled(chunkID: UUID)
}

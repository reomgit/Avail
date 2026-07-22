import Foundation

@MainActor
public protocol NarrationEngine: AnyObject {
    var voices: [NarrationVoice] { get }
    var events: AsyncStream<NarrationEvent> { get }

    func speak(_ request: NarrationRequest)
    func pause()
    func resume()
    func stop()
}

public extension NarrationEngine {
    func voices(matching languageCode: String?) -> [NarrationVoice] {
        guard let languageCode, !languageCode.isEmpty else { return voices }
        return voices.filter { $0.matches(languageCode: languageCode) }
    }
}

struct SpeechUtteranceSpec: Equatable {
    let id: UUID
    let text: String
    let rate: Float
    let voiceIdentifier: String?
}

@MainActor
protocol SpeechSynthesizerDriverDelegate: AnyObject {
    func speechSynthesizerDidStart(utteranceID: UUID)
    func speechSynthesizerWillSpeak(range: NSRange, utteranceID: UUID)
    func speechSynthesizerDidPause(utteranceID: UUID)
    func speechSynthesizerDidContinue(utteranceID: UUID)
    func speechSynthesizerDidFinish(utteranceID: UUID)
    func speechSynthesizerDidCancel(utteranceID: UUID)
}

@MainActor
protocol SpeechSynthesizerDriving: AnyObject {
    var delegate: (any SpeechSynthesizerDriverDelegate)? { get set }
    var installedVoices: [NarrationVoice] { get }

    func speak(_ utterance: SpeechUtteranceSpec)
    func pauseAtWord()
    func resume()
    func stopImmediately()
}

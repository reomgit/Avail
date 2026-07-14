@preconcurrency import AVFAudio
import Foundation

@MainActor
public final class SystemNarrationEngine: NarrationEngine {
    private let driver: any SpeechSynthesizerDriving
    private let eventStream: AsyncStream<NarrationEvent>
    private let eventContinuation: AsyncStream<NarrationEvent>.Continuation
    private struct UtteranceContext {
        let chunkID: UUID
        let utf16BaseOffset: Int
    }

    private var contextsByUtteranceID: [UUID: UtteranceContext] = [:]

    public var voices: [NarrationVoice] {
        driver.installedVoices
    }

    public var events: AsyncStream<NarrationEvent> {
        eventStream
    }

    public convenience init() {
        self.init(driver: SystemSpeechSynthesizerDriver())
    }

    init(driver: any SpeechSynthesizerDriving) {
        self.driver = driver
        (eventStream, eventContinuation) = AsyncStream.makeStream(of: NarrationEvent.self)
        driver.delegate = nil
        driver.delegate = self
    }

    public func speak(_ request: NarrationRequest) {
        let voiceIdentifier = selectedVoiceIdentifier(for: request)
        if let requestedIdentifier = request.voiceIdentifier,
           !voices.contains(where: { $0.id == requestedIdentifier }) {
            eventContinuation.yield(
                .voiceFallback(
                    requestedIdentifier: requestedIdentifier,
                    selectedIdentifier: voiceIdentifier
                )
            )
        }

        let utteranceID = UUID()
        let clampedOffset = min(max(0, request.startUTF16Offset), request.chunk.text.utf16.count)
        contextsByUtteranceID[utteranceID] = UtteranceContext(
            chunkID: request.chunk.id,
            utf16BaseOffset: clampedOffset
        )
        driver.speak(
            SpeechUtteranceSpec(
                id: utteranceID,
                text: (request.chunk.text as NSString).substring(from: clampedOffset),
                rate: request.rate,
                voiceIdentifier: voiceIdentifier
            )
        )
    }

    public func pause() {
        driver.pauseAtWord()
    }

    public func resume() {
        driver.resume()
    }

    public func stop() {
        driver.stopImmediately()
    }

    private func selectedVoiceIdentifier(for request: NarrationRequest) -> String? {
        if let requestedIdentifier = request.voiceIdentifier,
           voices.contains(where: { $0.id == requestedIdentifier }) {
            return requestedIdentifier
        }

        if let languageCode = request.languageCode {
            let normalizedLanguage = NarrationVoice.normalizedLanguageTag(languageCode)
            if let exactMatch = voices.first(where: {
                NarrationVoice.normalizedLanguageTag($0.languageCode) == normalizedLanguage
            }) {
                return exactMatch.id
            }
            if let languageMatch = voices.first(where: { $0.matches(languageCode: languageCode) }) {
                return languageMatch.id
            }
        }

        return voices.first?.id
    }
}

extension SystemNarrationEngine: SpeechSynthesizerDriverDelegate {
    func speechSynthesizerDidStart(utteranceID: UUID) {
        emit({ .started(chunkID: $0) }, utteranceID: utteranceID)
    }

    func speechSynthesizerWillSpeak(range: NSRange, utteranceID: UUID) {
        guard let context = contextsByUtteranceID[utteranceID] else { return }
        let sourceRange = NSRange(
            location: context.utf16BaseOffset + range.location,
            length: range.length
        )
        eventContinuation.yield(.willSpeakRange(chunkID: context.chunkID, range: sourceRange))
    }

    func speechSynthesizerDidPause(utteranceID: UUID) {
        emit({ .paused(chunkID: $0) }, utteranceID: utteranceID)
    }

    func speechSynthesizerDidContinue(utteranceID: UUID) {
        emit({ .resumed(chunkID: $0) }, utteranceID: utteranceID)
    }

    func speechSynthesizerDidFinish(utteranceID: UUID) {
        emit({ .finished(chunkID: $0) }, utteranceID: utteranceID)
        contextsByUtteranceID.removeValue(forKey: utteranceID)
    }

    func speechSynthesizerDidCancel(utteranceID: UUID) {
        emit({ .cancelled(chunkID: $0) }, utteranceID: utteranceID)
        contextsByUtteranceID.removeValue(forKey: utteranceID)
    }

    private func emit(
        _ event: (UUID) -> NarrationEvent,
        utteranceID: UUID
    ) {
        guard let context = contextsByUtteranceID[utteranceID] else { return }
        eventContinuation.yield(event(context.chunkID))
    }
}

@MainActor
private final class SystemSpeechSynthesizerDriver: NSObject, SpeechSynthesizerDriving {
    weak var delegate: (any SpeechSynthesizerDriverDelegate)?

    var installedVoices: [NarrationVoice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            NarrationVoice(id: $0.identifier, name: $0.name, languageCode: $0.language)
        }
    }

    private let synthesizer: AVSpeechSynthesizer
    private var utteranceIDs: [ObjectIdentifier: UUID] = [:]

    init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ utterance: SpeechUtteranceSpec) {
        let systemUtterance = AVSpeechUtterance(string: utterance.text)
        systemUtterance.rate = utterance.rate
        if let voiceIdentifier = utterance.voiceIdentifier {
            systemUtterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        utteranceIDs[ObjectIdentifier(systemUtterance)] = utterance.id
        synthesizer.speak(systemUtterance)
    }

    func pauseAtWord() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stopImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension SystemSpeechSynthesizerDriver: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        withUtteranceID(for: utterance) { delegate?.speechSynthesizerDidStart(utteranceID: $0) }
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        withUtteranceID(for: utterance) {
            delegate?.speechSynthesizerWillSpeak(range: characterRange, utteranceID: $0)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        withUtteranceID(for: utterance) { delegate?.speechSynthesizerDidPause(utteranceID: $0) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        withUtteranceID(for: utterance) { delegate?.speechSynthesizerDidContinue(utteranceID: $0) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        withUtteranceID(for: utterance) { delegate?.speechSynthesizerDidFinish(utteranceID: $0) }
        utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        withUtteranceID(for: utterance) { delegate?.speechSynthesizerDidCancel(utteranceID: $0) }
        utteranceIDs.removeValue(forKey: ObjectIdentifier(utterance))
    }

    private func withUtteranceID(for utterance: AVSpeechUtterance, perform action: (UUID) -> Void) {
        guard let utteranceID = utteranceIDs[ObjectIdentifier(utterance)] else { return }
        action(utteranceID)
    }
}

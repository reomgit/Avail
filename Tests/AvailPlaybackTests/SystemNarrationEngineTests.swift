import AvailCore
import Foundation
@testable import AvailPlayback
import XCTest

@MainActor
final class SystemNarrationEngineTests: XCTestCase {
    func testVoicesUseInstalledInventoryAndFilterByBCP47Language() {
        let driver = FakeSpeechSynthesizerDriver(voices: Self.voices)
        let engine = SystemNarrationEngine(driver: driver)

        XCTAssertEqual(engine.voices, Self.voices)
        XCTAssertEqual(
            engine.voices(matching: "en-AU").map(\.id),
            ["voice.en-us", "voice.en-gb"]
        )
        XCTAssertEqual(engine.voices(matching: "fr-FR").map(\.id), ["voice.fr-fr"])
    }

    func testMissingSavedVoiceSelectsLanguageFallbackAndEmitsEvent() async {
        let driver = FakeSpeechSynthesizerDriver(voices: Self.voices)
        let engine = SystemNarrationEngine(driver: driver)
        var events = engine.events.makeAsyncIterator()

        engine.speak(
            NarrationRequest(
                chunk: Self.chunk,
                voiceIdentifier: "voice.uninstalled",
                languageCode: "en-GB",
                rate: 0.46
            )
        )

        XCTAssertEqual(driver.spoken.last?.text, Self.chunk.text)
        XCTAssertEqual(driver.spoken.last?.rate, 0.46)
        XCTAssertEqual(driver.spoken.last?.voiceIdentifier, "voice.en-gb")
        let event = await events.next()
        XCTAssertEqual(
            event,
            .voiceFallback(
                requestedIdentifier: "voice.uninstalled",
                selectedIdentifier: "voice.en-gb"
            )
        )
    }

    func testValidVoiceAndRateAreAssignedToUtterance() {
        let driver = FakeSpeechSynthesizerDriver(voices: Self.voices)
        let engine = SystemNarrationEngine(driver: driver)

        engine.speak(
            NarrationRequest(
                chunk: Self.chunk,
                voiceIdentifier: "voice.fr-fr",
                languageCode: "en-US",
                rate: 0.51
            )
        )

        XCTAssertEqual(driver.spoken.last?.voiceIdentifier, "voice.fr-fr")
        XCTAssertEqual(driver.spoken.last?.rate, 0.51)
    }

    func testStartOffsetSpeaksSuffixAndMapsDelegateRangeBackToOriginalChunk() async {
        let driver = FakeSpeechSynthesizerDriver(voices: Self.voices)
        let engine = SystemNarrationEngine(driver: driver)
        var events = engine.events.makeAsyncIterator()

        engine.speak(NarrationRequest(chunk: Self.chunk, rate: 0.5, startUTF16Offset: 7))
        let utteranceID = try! XCTUnwrap(driver.spoken.last?.id)
        driver.emitRange(NSRange(location: 0, length: 2), utteranceID: utteranceID)

        XCTAssertEqual(driver.spoken.last?.text, (Self.chunk.text as NSString).substring(from: 7))
        let event = await events.next()
        XCTAssertEqual(event, .willSpeakRange(chunkID: Self.chunk.id, range: NSRange(location: 7, length: 2)))
    }

    func testPauseResumeAndStopForwardToRetainedSynthesizer() {
        var driver: FakeSpeechSynthesizerDriver? = FakeSpeechSynthesizerDriver(voices: Self.voices)
        weak let retainedDriver = driver
        var engine: SystemNarrationEngine? = SystemNarrationEngine(driver: driver!)

        driver = nil
        XCTAssertNotNil(retainedDriver)

        engine?.pause()
        engine?.resume()
        engine?.stop()

        XCTAssertEqual(retainedDriver?.pauseAtWordCallCount, 1)
        XCTAssertEqual(retainedDriver?.resumeCallCount, 1)
        XCTAssertEqual(retainedDriver?.stopImmediatelyCallCount, 1)

        engine = nil
        XCTAssertNil(retainedDriver)
    }

    func testDriverCallbacksMapToChunkScopedNarrationEventsAndPreserveUTF16Range() async {
        let driver = FakeSpeechSynthesizerDriver(voices: Self.voices)
        let engine = SystemNarrationEngine(driver: driver)
        var events = engine.events.makeAsyncIterator()
        engine.speak(NarrationRequest(chunk: Self.chunk, rate: 0.5))
        let utteranceID = try! XCTUnwrap(driver.spoken.last?.id)
        let range = NSRange(location: 7, length: 5)

        driver.emitStart(utteranceID)
        driver.emitRange(range, utteranceID: utteranceID)
        driver.emitPause(utteranceID)
        driver.emitContinue(utteranceID)
        driver.emitCancel(utteranceID)
        engine.speak(NarrationRequest(chunk: Self.chunk, rate: 0.5))
        let finishedUtteranceID = try! XCTUnwrap(driver.spoken.last?.id)
        driver.emitFinish(finishedUtteranceID)

        var received: [NarrationEvent] = []
        for _ in 0..<6 {
            if let event = await events.next() { received.append(event) }
        }
        XCTAssertEqual(
            received,
            [
                .started(chunkID: Self.chunk.id),
                .willSpeakRange(chunkID: Self.chunk.id, range: range),
                .paused(chunkID: Self.chunk.id),
                .resumed(chunkID: Self.chunk.id),
                .cancelled(chunkID: Self.chunk.id),
                .finished(chunkID: Self.chunk.id),
            ]
        )
    }

    private static let voices = [
        NarrationVoice(id: "voice.en-us", name: "Avery", languageCode: "en-US"),
        NarrationVoice(id: "voice.en-gb", name: "Jamie", languageCode: "en-GB"),
        NarrationVoice(id: "voice.fr-fr", name: "Camille", languageCode: "fr-FR"),
    ]

    private static let chunk = SpeechChunk(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        sectionID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        ordinal: 0,
        text: "Listen to this local narration sample.",
        wordCount: 6,
        locator: .pdf(pageIndex: 0),
        sourceRange: SourceTextRange(utf16Location: 0, utf16Length: 38)
    )
}

@MainActor
private final class FakeSpeechSynthesizerDriver: SpeechSynthesizerDriving {
    weak var delegate: (any SpeechSynthesizerDriverDelegate)?
    let installedVoices: [NarrationVoice]
    private(set) var spoken: [SpeechUtteranceSpec] = []
    private(set) var pauseAtWordCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var stopImmediatelyCallCount = 0

    init(voices: [NarrationVoice]) {
        installedVoices = voices
    }

    func speak(_ utterance: SpeechUtteranceSpec) {
        spoken.append(utterance)
    }

    func pauseAtWord() {
        pauseAtWordCallCount += 1
    }

    func resume() {
        resumeCallCount += 1
    }

    func stopImmediately() {
        stopImmediatelyCallCount += 1
    }

    func emitStart(_ utteranceID: UUID) {
        delegate?.speechSynthesizerDidStart(utteranceID: utteranceID)
    }

    func emitRange(_ range: NSRange, utteranceID: UUID) {
        delegate?.speechSynthesizerWillSpeak(range: range, utteranceID: utteranceID)
    }

    func emitPause(_ utteranceID: UUID) {
        delegate?.speechSynthesizerDidPause(utteranceID: utteranceID)
    }

    func emitContinue(_ utteranceID: UUID) {
        delegate?.speechSynthesizerDidContinue(utteranceID: utteranceID)
    }

    func emitFinish(_ utteranceID: UUID) {
        delegate?.speechSynthesizerDidFinish(utteranceID: utteranceID)
    }

    func emitCancel(_ utteranceID: UUID) {
        delegate?.speechSynthesizerDidCancel(utteranceID: utteranceID)
    }
}

import AvailCore
import AvailPlayback
import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class GeneratedNarrationEngineTests: XCTestCase {
    func testStopCancelsObsoletePhrasePreparation() async throws {
        let engine = GeneratedNarrationEngine(
            cacheURL: FileManager.default.temporaryDirectory.appending(path: "AvailAudioTest-\(UUID().uuidString)"),
            available: { [] },
            generate: { _, _ in
                try await Task.sleep(for: .seconds(30))
                return GeneratedAudio(wavData: Data(), sampleRate: 24_000)
            }
        )
        let text = "A short generated phrase."
        let request = NarrationRequest(
            chunk: SpeechChunk(
                id: UUID(), sectionID: UUID(), ordinal: 0, text: text, wordCount: 4,
                locator: .pdf(pageIndex: 0),
                sourceRange: SourceTextRange(utf16Location: 0, utf16Length: text.utf16.count)
            ),
            voiceIdentifier: "neural:test"
        )
        var events = engine.events.makeAsyncIterator()

        engine.speak(request)
        let preparation = await events.next()
        engine.stop()
        let cancelled = await events.next()

        XCTAssertEqual(preparation, .preparing(chunkID: request.chunk.id))
        XCTAssertEqual(cancelled, .cancelled(chunkID: request.chunk.id))
    }
}

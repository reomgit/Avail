import AvailCore
import AvailPlayback
import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class GeneratedNarrationEngineTests: XCTestCase {
    func testPreparedFirstPhraseIsReusedByPlay() async throws {
        let cache = FileManager.default.temporaryDirectory.appending(path: "AvailAudioTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        var generationCount = 0
        let engine = GeneratedNarrationEngine(
            cacheURL: cache,
            available: { [] },
            generate: { _, _ in
                generationCount += 1
                return GeneratedAudio(
                    wavData: Self.testWAV(),
                    sampleRate: 24_000
                )
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

        try await engine.prepareAudio(for: request)
        XCTAssertEqual(generationCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).filter { $0.hasSuffix(".wav") }.count, 1)

        engine.speak(request)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(generationCount, 1, "Play should use the audio prepared before it was enabled")
        engine.stop()
    }

    private static func testWAV() -> Data {
        let frameCount = 24_000
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + frameCount * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(24_000))
        append(UInt32(48_000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(frameCount * 2))
        data.append(Data(count: frameCount * 2))
        return data
    }

    func testModelPreparationCompletesBeforeGeneratingFirstPhrase() async throws {
        enum PreparationFailure: Error { case unavailable }

        var didGenerate = false
        let engine = GeneratedNarrationEngine(
            cacheURL: FileManager.default.temporaryDirectory.appending(path: "AvailAudioTest-\(UUID().uuidString)"),
            available: { [] },
            prepare: { _ in throw PreparationFailure.unavailable },
            generate: { _, _ in
                didGenerate = true
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
        XCTAssertEqual(preparation, .preparing(chunkID: request.chunk.id))
        guard case let .failed(chunkID, _) = await events.next() else {
            return XCTFail("Expected model preparation to fail before audio generation.")
        }
        XCTAssertEqual(chunkID, request.chunk.id)
        XCTAssertFalse(didGenerate)
    }

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

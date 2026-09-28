import AVFAudio
import XCTest
@testable import AvailPlayback

final class GeneratedAudioWAVEncoderTests: XCTestCase {
    func testEncodesModelSamplesInAFormatAVAudioPlayerCanOpen() throws {
        let samples = (0..<24_000).map { frame in
            sin(Float(frame) * 2 * .pi * 440 / 24_000) * 0.2
        }

        let data = try GeneratedAudioWAVEncoder.encode(samples: samples, sampleRate: 24_000)
        let player = try AVAudioPlayer(data: data)

        XCTAssertEqual(player.numberOfChannels, 1)
        XCTAssertEqual(player.duration, 1, accuracy: 0.01)
    }
}

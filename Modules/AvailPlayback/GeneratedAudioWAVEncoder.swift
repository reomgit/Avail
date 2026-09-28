@preconcurrency import AVFAudio
import Foundation

/// Converts generated mono samples to a WAV file that AVAudioPlayer can open.
public enum GeneratedAudioWAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int) throws -> Data {
        guard (8_000...192_000).contains(sampleRate), !samples.isEmpty, samples.count <= 10_000_000 else {
            throw NeuralHelperError.invalidPhrase("The model returned unsupported audio.")
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 1,
                interleaved: false
            ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData?[0]
        else {
            throw NeuralHelperError.invalidPhrase("Avail could not prepare the generated audio.")
        }

        buffer.frameLength = frameCount
        for (index, sample) in samples.enumerated() {
            guard sample.isFinite else {
                throw NeuralHelperError.invalidPhrase("The model returned invalid audio samples.")
            }
            channelData[index] = sample
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "AvailGeneratedAudio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            let audioFile = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            try audioFile.write(from: buffer)
        } catch {
            throw NeuralHelperError.invalidPhrase(
                "Avail could not package the model's audio for playback (\(sampleRate) Hz, \(samples.count) samples)."
            )
        }

        do {
            return try Data(contentsOf: outputURL)
        } catch {
            throw NeuralHelperError.invalidPhrase("Avail could not read the generated audio for playback.")
        }
    }
}

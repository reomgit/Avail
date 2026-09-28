@preconcurrency import AVFAudio
import AvailCore
import AvailPlayback
import CryptoKit
import Foundation

@MainActor
final class GeneratedNarrationEngine: NSObject, NarrationEngine, AVAudioPlayerDelegate {
    typealias Generator = @MainActor (String, String) async throws -> GeneratedAudio
    typealias CacheIdentity = @MainActor (String) async throws -> String
    typealias Preparer = @MainActor (String) async throws -> Void

    private let available: () -> [NarrationVoice]
    private let prepare: Preparer
    private let generate: Generator
    private let cacheIdentity: CacheIdentity
    private let cacheURL: URL
    private let stream: AsyncStream<NarrationEvent>
    private let continuation: AsyncStream<NarrationEvent>.Continuation
    private let splitter = SpeechPhraseSplitter()
    private var generation: Task<Void, Never>?
    private var progress: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var request: NarrationRequest?
    private var phrase: SpeechPhrase?
    private var clipKey: String?
    private var sampleRate = 0
    private var generationID = UUID()
    private var pausedDuringPreparation = false

    var voices: [NarrationVoice] { available() }
    var events: AsyncStream<NarrationEvent> { stream }

    init(
        cacheURL: URL,
        available: @escaping () -> [NarrationVoice],
        cacheIdentity: @escaping CacheIdentity = { $0 },
        prepare: @escaping Preparer = { _ in },
        generate: @escaping Generator
    ) {
        self.cacheURL = cacheURL
        self.available = available
        self.cacheIdentity = cacheIdentity
        self.prepare = prepare
        self.generate = generate
        (stream, continuation) = AsyncStream.makeStream(of: NarrationEvent.self)
        super.init()
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }

    func speak(_ request: NarrationRequest) {
        stop()
        self.request = request
        guard let phrase = splitter.next(in: request.chunk, fromUTF16Offset: request.startUTF16Offset) else {
            continuation.yield(.finished(chunkID: request.chunk.id))
            return
        }
        self.phrase = phrase
        let voiceID = request.voiceIdentifier ?? ""
        let generationID = UUID()
        self.generationID = generationID
        continuation.yield(.preparing(chunkID: request.chunk.id))
        let audioResume = request.audioResume
        generation = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedVoiceID = try await self.cacheIdentity(voiceID)
                guard !Task.isCancelled, self.generationID == generationID else { return }
                try await self.prepare(voiceID)
                guard !Task.isCancelled, self.generationID == generationID else { return }
                let key = Self.key(voiceID: resolvedVoiceID, text: phrase.text)
                self.clipKey = key
                let clipURL = self.cacheURL.appending(path: "\(key).wav")
                let audio: GeneratedAudio
                let canResume =
                    audioResume?.clipKey == key
                    && audioResume?.phraseStartUTF16Offset == phrase.range.location
                    && audioResume?.phraseEndUTF16Offset == NSMaxRange(phrase.range)
                    && audioResume.map { (8_000...192_000).contains($0.sampleRate) && $0.frameOffset >= 0 } == true
                    && FileManager.default.fileExists(atPath: clipURL.path)
                if canResume {
                    audio = GeneratedAudio(
                        wavData: try Data(contentsOf: clipURL),
                        sampleRate: audioResume?.sampleRate ?? 0
                    )
                } else {
                    audio = try await generate(voiceID, phrase.text)
                    try Task.checkCancellation()
                    try audio.wavData.write(to: clipURL, options: .atomic)
                    self.pruneCache(keeping: key)
                }
                guard !Task.isCancelled, self.generationID == generationID else { return }
                try self.start(audio: audio, at: clipURL, resume: canResume ? audioResume : nil)
            } catch is CancellationError {
                return
            } catch {
                guard self.generationID == generationID else { return }
                self.continuation.yield(.failed(chunkID: request.chunk.id, reason: error.localizedDescription))
            }
        }
    }

    func pause() {
        if let player { player.pause() } else { pausedDuringPreparation = true }
        publishPosition()
        if let request { continuation.yield(.paused(chunkID: request.chunk.id)) }
    }

    func resume() {
        pausedDuringPreparation = false
        player?.play()
        if let request { continuation.yield(.resumed(chunkID: request.chunk.id)) }
    }

    func stop() {
        let stoppedChunkID = request?.chunk.id
        if player != nil { publishPosition() }
        if let stoppedChunkID { continuation.yield(.cancelled(chunkID: stoppedChunkID)) }
        generationID = UUID()
        generation?.cancel()
        generation = nil
        progress?.cancel()
        progress = nil
        player?.stop()
        player = nil
        request = nil
        phrase = nil
        clipKey = nil
        pausedDuringPreparation = false
    }

    private func start(audio: GeneratedAudio, at url: URL, resume: AudioResumePoint?) throws {
        guard let request, let phrase, let clipKey else { return }
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.enableRate = true
        player.rate = min(2, max(0.5, request.speedMultiplier))
        player.prepareToPlay()
        self.player = player
        sampleRate = audio.sampleRate
        if resume?.clipKey == clipKey, let frame = resume?.frameOffset, frame > 0 {
            player.currentTime = min(Double(frame) / Double(audio.sampleRate), max(0, player.duration - 0.01))
        }
        continuation.yield(.willSpeakRange(chunkID: request.chunk.id, range: phrase.range))
        publishPosition()
        if !pausedDuringPreparation {
            guard player.play() else { throw LocalSpeechServerError.invalidAudio }
            continuation.yield(.started(chunkID: request.chunk.id))
        }
        progress = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.publishPosition()
            }
        }
    }

    private func publishPosition() {
        guard let request, let phrase, let clipKey, let player, sampleRate > 0 else { return }
        let frame = Int64(max(0, (player.currentTime * Double(sampleRate)).rounded(.down)))
        continuation.yield(
            .audioPosition(
                chunkID: request.chunk.id,
                range: phrase.range,
                resume: AudioResumePoint(
                    clipKey: clipKey,
                    phraseStartUTF16Offset: phrase.range.location,
                    phraseEndUTF16Offset: NSMaxRange(phrase.range),
                    frameOffset: frame,
                    sampleRate: sampleRate
                )
            ))
    }

    private func pruneCache(keeping currentKey: String) {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
        else { return }
        let wavFiles = files.filter { $0.pathExtension == "wav" }
        var sized = wavFiles.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize
            else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        let limit = 512 * 1_024 * 1_024
        for file in sized.filter({ $0.0.lastPathComponent != "\(currentKey).wav" }).sorted(by: { $0.2 < $1.2 }) {
            guard total > limit else { break }
            try? FileManager.default.removeItem(at: file.0)
            total -= file.1
        }
        sized.removeAll(keepingCapacity: false)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player, let request, let phrase else { return }
        progress?.cancel()
        progress = nil
        self.player = nil
        if !flag {
            continuation.yield(.failed(chunkID: request.chunk.id, reason: "The generated voice audio stopped unexpectedly. Choose the voice again in Settings."))
        } else if splitter.next(in: request.chunk, fromUTF16Offset: NSMaxRange(phrase.range)) != nil {
            continuation.yield(.phraseFinished(chunkID: request.chunk.id, nextUTF16Offset: NSMaxRange(phrase.range)))
        } else {
            continuation.yield(.finished(chunkID: request.chunk.id))
        }
    }

    private static func key(voiceID: String, text: String) -> String {
        let digest = SHA256.hash(data: Data((voiceID + "\0" + text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

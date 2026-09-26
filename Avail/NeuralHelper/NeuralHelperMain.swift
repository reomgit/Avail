import AvailPlayback
import Foundation
import MLXAudioTTS

private final class XPCReply: @unchecked Sendable {
    let callback: (Data?, Int, String?) -> Void

    init(_ callback: @escaping (Data?, Int, String?) -> Void) {
        self.callback = callback
    }
}

private actor FishModelHost {
    private var loadedModel: FishSpeechModel?
    private var loadedPath: String?
    private var loadedFingerprint: String?
    private let synthesisQueue = NeuralSynthesisQueue()

    func synthesize(folder: URL, text: String) async throws -> (Data, Int) {
        try await synthesisQueue.run { [self] in
            try await generate(folder: folder, text: text)
        }
    }

    private func generate(folder: URL, text: String) async throws -> (Data, Int) {
        try Task.checkCancellation()
        let fingerprint = try FishS2ModelFolder.cacheFingerprint(at: folder)
        let path = folder.standardizedFileURL.path
        let model: FishSpeechModel
        if loadedPath == path, loadedFingerprint == fingerprint, let loadedModel {
            model = loadedModel
        } else {
            model = try await FishSpeechModel.fromModelDirectory(folder)
            try Task.checkCancellation()
            loadedModel = model
            loadedPath = path
            loadedFingerprint = fingerprint
        }

        let samples = try await model.generate(
            text: text, voice: nil, refAudio: nil, refText: nil, language: nil
        ).asArray(Float.self)
        try Task.checkCancellation()
        return (try WAVEncoder.encode(samples: samples, sampleRate: model.sampleRate), model.sampleRate)
    }
}

private enum WAVEncoder {
    static func encode(samples: [Float], sampleRate: Int) throws -> Data {
        guard sampleRate > 0, sampleRate <= 192_000, !samples.isEmpty,
            samples.count <= 10_000_000
        else {
            throw NeuralHelperError.invalidPhrase("The model returned unsupported audio.")
        }

        let byteCount = samples.count * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + byteCount)
        func write(_ text: String) { data.append(contentsOf: text.utf8) }
        func write16(_ number: UInt16) {
            data.append(UInt8(truncatingIfNeeded: number))
            data.append(UInt8(truncatingIfNeeded: number >> 8))
        }
        func write32(_ number: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                data.append(UInt8(truncatingIfNeeded: number >> shift))
            }
        }

        write("RIFF")
        write32(UInt32(36 + byteCount))
        write("WAVEfmt ")
        write32(16)
        write16(1)  // PCM
        write16(1)  // Mono
        write32(UInt32(sampleRate))
        write32(UInt32(sampleRate * 2))
        write16(2)
        write16(16)
        write("data")
        write32(UInt32(byteCount))
        for sample in samples {
            guard sample.isFinite else {
                throw NeuralHelperError.invalidPhrase("The model returned invalid audio samples.")
            }
            let pcm = Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded())
            write16(UInt16(bitPattern: pcm))
        }
        return data
    }
}

private final class NeuralHelperService: NSObject, NeuralHelperXPCProtocol, @unchecked Sendable {
    private let host = FishModelHost()
    private let lock = NSLock()
    private var activeTasks: [String: Task<Void, Never>] = [:]

    func validateModel(bookmark: Data, reply: @escaping (String?) -> Void) {
        do {
            let folder = try resolveFolder(bookmark)
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            try FishS2ModelFolder.validate(at: folder)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func synthesize(
        requestID: String,
        bookmark: Data,
        text: String,
        reply: @escaping (Data?, Int, String?) -> Void
    ) {
        do {
            try NeuralPhrase.validate(text)
            guard UUID(uuidString: requestID) != nil else {
                throw NeuralHelperError.invalidPhrase("Invalid narration request.")
            }
        } catch {
            reply(nil, 0, error.localizedDescription)
            return
        }

        let safeReply = XPCReply(reply)
        lock.lock()
        let task = Task.detached { [host] in
            do {
                try Task.checkCancellation()
                let folder = try Self.resolveFolder(bookmark)
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                let (audio, sampleRate) = try await host.synthesize(folder: folder, text: text)
                try Task.checkCancellation()
                safeReply.callback(audio, sampleRate, nil)
            } catch is CancellationError {
                safeReply.callback(nil, 0, "Narration generation was cancelled.")
            } catch {
                safeReply.callback(nil, 0, error.localizedDescription)
            }
            self.removeTask(requestID)
        }
        activeTasks[requestID] = task
        lock.unlock()
    }

    func cancel(requestID: String) {
        lock.lock()
        activeTasks[requestID]?.cancel()
        lock.unlock()
    }

    private func removeTask(_ requestID: String) {
        lock.lock()
        activeTasks.removeValue(forKey: requestID)
        lock.unlock()
    }

    private static func resolveFolder(_ bookmark: Data) throws -> URL {
        var stale = false
        let folder = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else {
            throw NeuralHelperError.invalidModel("Model folder access expired. Reconnect it in Voices settings.")
        }
        return folder
    }

    private func resolveFolder(_ bookmark: Data) throws -> URL {
        try Self.resolveFolder(bookmark)
    }
}

private final class NeuralHelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = NeuralHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NeuralHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

@main
private enum NeuralHelperMain {
    static func main() {
        let delegate = NeuralHelperDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        RunLoop.main.run()
    }
}

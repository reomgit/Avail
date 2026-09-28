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

    func prepare(folder: URL) async throws {
        try await synthesisQueue.run { [self] in
            _ = try await load(folder: folder)
        }
    }

    private func generate(folder: URL, text: String) async throws -> (Data, Int) {
        let model = try await load(folder: folder)
        let samples: [Float]
        do {
            samples = try await model.generate(
                text: text, voice: nil, refAudio: nil, refText: nil, language: nil
            ).asArray(Float.self)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NeuralHelperError.invalidPhrase(
                "Fish Audio could not generate this phrase. Check available memory and try again."
            )
        }
        try Task.checkCancellation()
        return (try GeneratedAudioWAVEncoder.encode(samples: samples, sampleRate: model.sampleRate), model.sampleRate)
    }

    private func load(folder: URL) async throws -> FishSpeechModel {
        try Task.checkCancellation()
        let fingerprint: String
        do {
            fingerprint = try FishS2ModelFolder.cacheFingerprint(at: folder)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NeuralHelperError {
            throw error
        } catch {
            throw NeuralHelperError.invalidModel(
                "Avail could not inspect the Fish Audio model files. Reconnect the folder and try again."
            )
        }
        let path = folder.standardizedFileURL.path
        if loadedPath == path, loadedFingerprint == fingerprint, let loadedModel {
            return loadedModel
        } else {
            let model: FishSpeechModel
            do {
                model = try await FishSpeechModel.fromModelDirectory(folder)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw NeuralHelperError.invalidModel(
                    "Avail could not load the Fish Audio model into memory. Check that its files are available and your Mac has enough free memory, then try again."
                )
            }
            try Task.checkCancellation()
            loadedModel = model
            loadedPath = path
            loadedFingerprint = fingerprint
            return model
        }
    }
}

private final class NeuralHelperService: NSObject, NeuralHelperXPCProtocol, @unchecked Sendable {
    private let host = FishModelHost()
    private let lock = NSLock()
    private var activeTasks: [String: Task<Void, Never>] = [:]

    func validateModel(bookmark: Data, reply: @escaping (String?) -> Void) {
        do {
            let folder = try resolveFolder(bookmark)
            defer { folder.stopAccessingSecurityScopedResource() }
            try FishS2ModelFolder.validate(at: folder)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }

    func prepareModel(bookmark: Data, reply: @escaping (String?) -> Void) {
        let safeReply = XPCReply { _, _, error in reply(error) }
        Task.detached { [host] in
            do {
                let folder = try Self.resolveFolder(bookmark)
                defer { folder.stopAccessingSecurityScopedResource() }
                try await host.prepare(folder: folder)
                safeReply.callback(nil, 0, nil)
            } catch is CancellationError {
                safeReply.callback(nil, 0, "Voice model preparation was cancelled.")
            } catch {
                safeReply.callback(nil, 0, error.localizedDescription)
            }
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
                defer { folder.stopAccessingSecurityScopedResource() }
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
        let folder: URL
        do {
            // The app sends a transient options-empty bookmark for this XPC process.
            folder = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw NeuralHelperError.invalidModel(
                "The neural helper could not reopen the model folder. Reconnect it in Voices settings."
            )
        }
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

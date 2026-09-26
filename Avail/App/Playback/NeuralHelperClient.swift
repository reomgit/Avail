import AvailPlayback
import Foundation

enum NeuralHelperClientError: LocalizedError {
    case unavailable
    case unsupportedMac
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The local voice helper is unavailable. Try again or choose a macOS voice."
        case .unsupportedMac:
            "Imported neural voices require an Apple Silicon Mac. Choose a macOS voice."
        case .invalidResponse:
            "The local voice helper returned invalid audio. Try again or choose a macOS voice."
        case .service(let detail):
            detail
        }
    }
}

private final class XPCContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancellationRequested = false
    private var outcome: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if cancellationRequested {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        if let outcome {
            lock.unlock()
            continuation.resume(with: outcome)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func complete(_ result: Result<Value, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil && !cancellationRequested && outcome == nil {
            outcome = result
        }
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

@MainActor
final class NeuralHelperClient {
    private var connection: NSXPCConnection?

    func validateModel(bookmark: Data) async throws {
        #if arch(arm64)
            let response = XPCContinuation<Void>()
            let remote = try proxy { response.complete(.failure($0)) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                response.install(continuation)
                remote.validateModel(bookmark: bookmark) { error in
                    if let error {
                        response.complete(.failure(NeuralHelperClientError.service(error)))
                    } else {
                        response.complete(.success(()))
                    }
                }
            }
        #else
            throw NeuralHelperClientError.unsupportedMac
        #endif
    }

    func synthesize(requestID: UUID, bookmark: Data, text: String) async throws -> (wav: Data, sampleRate: Int) {
        try NeuralPhrase.validate(text)
        #if arch(arm64)
            let response = XPCContinuation<(wav: Data, sampleRate: Int)>()
            let remote = try proxy { response.complete(.failure($0)) }
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    response.install(continuation)
                    remote.synthesize(requestID: requestID.uuidString, bookmark: bookmark, text: text) {
                        audio, sampleRate, error in
                        if let error {
                            response.complete(.failure(NeuralHelperClientError.service(error)))
                        } else if let audio, !audio.isEmpty, sampleRate > 0 {
                            response.complete(.success((wav: audio, sampleRate: sampleRate)))
                        } else {
                            response.complete(.failure(NeuralHelperClientError.invalidResponse))
                        }
                    }
                }
            } onCancel: {
                response.cancel()
                Task { @MainActor in self.cancel(requestID: requestID) }
            }
        #else
            throw NeuralHelperClientError.unsupportedMac
        #endif
    }

    func cancel(requestID: UUID) {
        #if arch(arm64)
            (connection?.remoteObjectProxy as? NeuralHelperXPCProtocol)?.cancel(requestID: requestID.uuidString)
        #endif
    }

    private func proxy(errorHandler: @escaping (Error) -> Void) throws -> NeuralHelperXPCProtocol {
        if connection == nil {
            let created = NSXPCConnection(serviceName: NeuralHelperService.name)
            created.remoteObjectInterface = NSXPCInterface(with: NeuralHelperXPCProtocol.self)
            created.interruptionHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            created.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            created.resume()
            connection = created
        }
        guard let remote = connection?.remoteObjectProxyWithErrorHandler(errorHandler) as? NeuralHelperXPCProtocol
        else {
            throw NeuralHelperClientError.unavailable
        }
        return remote
    }
}

import Foundation
import CryptoKit

/// The Objective-C compatible boundary shared by the universal app and the arm64 XPC service.
@objc public protocol NeuralHelperXPCProtocol {
    func validateModel(bookmark: Data, reply: @escaping (String?) -> Void)
    func prepareModel(bookmark: Data, reply: @escaping (String?) -> Void)
    func synthesize(
        requestID: String,
        bookmark: Data,
        text: String,
        reply: @escaping (Data?, Int, String?) -> Void
    )
    func cancel(requestID: String)
}

public enum NeuralHelperService {
    public static let name = "org.openavail.Avail.NeuralHelper"
}

/// Serializes MLX work while allowing each caller to cancel only its own queued or active request.
public actor NeuralSynthesisQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    public func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let previous = tail
        let task = Task<Value, Error> {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task {
            _ = try? await task.value
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

public enum NeuralPhrase {
    public static let maximumCharacters = 2_000

    public static func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NeuralHelperError.invalidPhrase("Passage is empty.")
        }
        guard text.count <= maximumCharacters else {
            throw NeuralHelperError.invalidPhrase("Passage is too long for a single phrase.")
        }
    }
}

public enum NeuralHelperError: LocalizedError {
    case invalidModel(String)
    case invalidPhrase(String)

    public var errorDescription: String? {
        switch self {
        case .invalidModel(let detail), .invalidPhrase(let detail): detail
        }
    }
}

/// A structural check only; model weights are validated by MLX while loading.
public enum FishS2ModelFolder {
    public static func validate(at folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw NeuralHelperError.invalidModel("The Fish Audio S2 Pro model folder is unavailable.")
        }

        let config = try requiredFile("config.json", in: folder)
        let data = try Data(contentsOf: config)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let modelType = object["model_type"] as? String,
            modelType == "fish_qwen3_omni"
        else {
            throw NeuralHelperError.invalidModel("This folder is not a Fish Audio S2 Pro MLX model (model_type must be fish_qwen3_omni).")
        }

        // The pinned upstream tokenizer writes these files when absent. Require both so a
        // linked user folder remains untouched and can be mounted read-only.
        _ = try requiredFile("tokenizer.json", in: folder)
        _ = try requiredFile("tokenizer_config.json", in: folder)
        _ = try requiredFile("codec.safetensors", in: folder)

        let modelWeights = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        .filter { $0.pathExtension == "safetensors" && $0.lastPathComponent != "codec.safetensors" }
        guard !modelWeights.isEmpty else {
            throw NeuralHelperError.invalidModel("The model is missing MLX model weights (.safetensors).")
        }
        for weight in modelWeights {
            try validateRegularFile(weight)
        }

        let index = folder.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            try validateRegularFile(index)
            let indexData = try Data(contentsOf: index)
            guard let contents = (try? JSONSerialization.jsonObject(with: indexData)) as? [String: Any],
                let map = contents["weight_map"] as? [String: String],
                !map.isEmpty
            else {
                throw NeuralHelperError.invalidModel("The Fish Audio S2 Pro weight index is invalid.")
            }
            for filename in Set(map.values) {
                guard filename == URL(fileURLWithPath: filename).lastPathComponent,
                    filename.hasSuffix(".safetensors")
                else {
                    throw NeuralHelperError.invalidModel("The Fish Audio S2 Pro weight index has an invalid filename.")
                }
                _ = try requiredFile(filename, in: folder)
            }
        }
    }

    /// Returns a cheap identity for the model files without reading large weight contents.
    /// File identifiers catch replacement at the same path; size and modification time catch
    /// in-place edits while avoiding a multi-gigabyte hash on every phrase.
    public static func cacheFingerprint(at folder: URL) throws -> String {
        try validate(at: folder)
        let directoryContents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        )
        let modelFiles = directoryContents.filter {
            ["config.json", "tokenizer.json", "tokenizer_config.json", "codec.safetensors", "model.safetensors.index.json"].contains($0.lastPathComponent)
                || $0.pathExtension == "safetensors"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let identity = try modelFiles.map { url -> String in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
            guard let size = values.fileSize else {
                throw NeuralHelperError.invalidModel("Avail cannot read the size of \(url.lastPathComponent).")
            }
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let resourceID = values.fileResourceIdentifier.map(String.init(describing:)) ?? ""
            return "\(url.lastPathComponent)\0\(size)\0\(modified)\0\(resourceID)"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func requiredFile(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NeuralHelperError.invalidModel("The model is missing \(name).")
        }
        try validateRegularFile(url)
        return url
    }

    private static func validateRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NeuralHelperError.invalidModel("The model contains an unsupported file link: \(url.lastPathComponent).")
        }
    }
}

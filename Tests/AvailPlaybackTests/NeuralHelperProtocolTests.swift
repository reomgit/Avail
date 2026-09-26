import AvailPlayback
import Foundation
import XCTest

final class NeuralHelperProtocolTests: XCTestCase {
    func testRejectsIncompleteFishModelWithoutTryingToLoadIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try FishS2ModelFolder.validate(at: folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("config.json"))
        }
    }

    func testRejectsNonFishConfiguration() throws {
        let folder = try makeModelFolder(config: "{\"model_type\":\"fish_speech\"}")
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try FishS2ModelFolder.validate(at: folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Fish Audio S2 Pro"))
        }
    }

    func testRejectsMalformedConfigurationWithModelSpecificMessage() throws {
        let folder = try makeModelFolder(config: "not JSON")
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try FishS2ModelFolder.validate(at: folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Fish Audio S2 Pro"))
        }
    }

    func testRequiresPrebuiltTokenizerToKeepLinkedFolderReadOnly() throws {
        let folder = try makeModelFolder(config: "{\"model_type\":\"fish_qwen3_omni\"}")
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertThrowsError(try FishS2ModelFolder.validate(at: folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("tokenizer.json"))
        }
    }

    func testAcceptsCompleteFishModelFileLayout() throws {
        let folder = try makeModelFolder(config: "{\"model_type\":\"fish_qwen3_omni\"}")
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["tokenizer.json", "tokenizer_config.json", "model.safetensors", "codec.safetensors"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
        }

        XCTAssertNoThrow(try FishS2ModelFolder.validate(at: folder))
    }

    func testRejectsMissingReferencedWeightShard() throws {
        let folder = try makeModelFolder(config: "{\"model_type\":\"fish_qwen3_omni\"}")
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["tokenizer.json", "tokenizer_config.json", "model-00001-of-00002.safetensors", "codec.safetensors"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
        }
        try Data("{\"weight_map\":{\"a\":\"model-00001-of-00002.safetensors\",\"b\":\"model-00002-of-00002.safetensors\"}}".utf8)
            .write(to: folder.appendingPathComponent("model.safetensors.index.json"))

        XCTAssertThrowsError(try FishS2ModelFolder.validate(at: folder)) { error in
            XCTAssertTrue(error.localizedDescription.contains("model-00002-of-00002.safetensors"))
        }
    }

    func testRejectsLongPhraseBeforeGeneration() {
        XCTAssertThrowsError(try NeuralPhrase.validate(String(repeating: "a", count: 2_001)))
        XCTAssertNoThrow(try NeuralPhrase.validate("A short sentence."))
    }

    private func makeModelFolder(config: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(config.utf8).write(to: folder.appendingPathComponent("config.json"))
        return folder
    }
}

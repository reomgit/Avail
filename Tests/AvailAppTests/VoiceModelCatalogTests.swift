import Foundation
import XCTest
@testable import AvailApp

@MainActor
final class VoiceModelCatalogTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appending(path: "VoiceCatalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testLinkedModelPersistsAndLeavesSourceOnRemoval() throws {
        let source = try makeFishFixture()
        let catalog = try makeCatalog()
        let entry = try catalog.linkModel(at: source)
        XCTAssertEqual(entry.source, .linked)
        XCTAssertEqual(try makeCatalog().entries.map(\.id), [entry.id])
        let lease = try catalog.beginModelAccess(id: entry.id)
        XCTAssertEqual(lease.url.standardizedFileURL, source.standardizedFileURL)
        try catalog.remove(id: entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try makeCatalog().entries.isEmpty)
    }

    func testHelperTransferBookmarkResolvesInReceivingProcess() throws {
        let source = try makeFishFixture()
        let catalog = try makeCatalog()
        let entry = try catalog.linkModel(at: source)
        let lease = try catalog.beginModelAccess(id: entry.id)

        let transferBookmark = try lease.makeHelperTransferBookmark()
        var isStale = false
        let helperURL = try URL(
            resolvingBookmarkData: transferBookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        XCTAssertFalse(isStale)
        XCTAssertEqual(helperURL.standardizedFileURL, source.standardizedFileURL)
    }

    func testManagedCopySurvivesSourceRemovalAndNeedsConfirmationToTrash() async throws {
        let source = try makeFishFixture()
        let trashURL = sandbox.appending(path: "TestTrash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let catalog = try makeCatalog { url in
            try FileManager.default.moveItem(at: url, to: trashURL.appending(path: url.lastPathComponent))
        }
        let entry = try await catalog.copyModel(from: source)
        try FileManager.default.removeItem(at: source)
        let lease = try catalog.beginModelAccess(id: entry.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.url.appending(path: "config.json").path))
        XCTAssertThrowsError(try catalog.remove(id: entry.id))
        XCTAssertEqual(catalog.entries.count, 1)
        try catalog.remove(id: entry.id, confirmedManagedDeletion: true)
        XCTAssertTrue(catalog.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashURL.appending(path: entry.id.uuidString).path))
    }

    func testInterruptedStageIsRemovedWithoutDeletingRegisteredModel() async throws {
        let catalog = try makeCatalog()
        let entry = try await catalog.copyModel(from: makeFishFixture())
        let stage = sandbox.appending(path: "ApplicationSupport/Models/.stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        let reopened = try makeCatalog()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertEqual(reopened.entries.map(\.id), [entry.id])
        XCTAssertNoThrow(try reopened.beginModelAccess(id: entry.id))
    }

    func testMissingLinkedFolderKeepsCatalogEntryForReconnect() throws {
        let source = try makeFishFixture()
        let catalog = try makeCatalog()
        let entry = try catalog.linkModel(at: source)
        try FileManager.default.removeItem(at: source)

        let reopened = try makeCatalog()

        XCTAssertEqual(reopened.entries.map(\.id), [entry.id])
        XCTAssertThrowsError(try reopened.beginModelAccess(id: entry.id))
    }

    func testReconnectLinkedModelPreservesItsStableID() throws {
        let original = try makeFishFixture()
        let catalog = try makeCatalog()
        let entry = try catalog.linkModel(at: original)
        try FileManager.default.removeItem(at: original)
        let replacement = try makeFishFixture(named: "Replacement")

        let updated = try catalog.reconnectLinkedModel(id: entry.id, at: replacement)

        XCTAssertEqual(updated.id, entry.id)
        XCTAssertEqual(catalog.entries.map(\.id), [entry.id])
        XCTAssertEqual(try makeCatalog().beginModelAccess(id: entry.id).url.standardizedFileURL, replacement.standardizedFileURL)
    }

    func testInvalidModelAndEscapingSymlinkAreRejectedWithoutCatalogEntry() async throws {
        let source = try makeFishFixture()
        let catalog = try makeCatalog()
        try FileManager.default.removeItem(at: source.appending(path: "tokenizer.json"))
        XCTAssertThrowsError(try catalog.linkModel(at: source))
        try Data("{}".utf8).write(to: source.appending(path: "tokenizer.json"))
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "escape"),
            withDestinationURL: sandbox.appending(path: "outside")
        )
        do {
            _ = try await catalog.copyModel(from: source)
            XCTFail("Managed copy should reject a symbolic link")
        } catch {
            XCTAssertTrue(catalog.entries.isEmpty)
        }
        XCTAssertTrue(catalog.entries.isEmpty)
    }

    func testServerRequiresLiteralLoopbackAndPersistsConfiguration() throws {
        let catalog = try makeCatalog()
        XCTAssertThrowsError(
            try catalog.addServer(name: "Remote", baseURL: URL(string: "http://example.com:8080")!, modelID: "m", voiceID: "v")
        )
        XCTAssertThrowsError(
            try catalog.addServer(name: "Localhost", baseURL: URL(string: "http://localhost:8080")!, modelID: "m", voiceID: "v")
        )
        XCTAssertThrowsError(
            try catalog.addServer(name: "Other loopback", baseURL: URL(string: "http://127.0.0.2:8080")!, modelID: "m", voiceID: "v")
        )
        let entry = try catalog.addServer(name: "Local", baseURL: URL(string: "http://127.0.0.1:8080")!, modelID: "m", voiceID: "v")
        let ipv6 = try catalog.addServer(name: "IPv6", baseURL: URL(string: "http://[::1]:8081")!, modelID: "m", voiceID: "v")
        XCTAssertEqual(entry.source, .loopbackServer)
        XCTAssertEqual(try makeCatalog().entries.first?.serverURL, URL(string: "http://127.0.0.1:8080"))
        XCTAssertEqual(try makeCatalog().entries.first?.modelID, "m")
        XCTAssertEqual(ipv6.serverURL?.host(), "::1")
    }

    func testServerCredentialLivesInKeychainInsteadOfCatalogJSON() throws {
        let catalog = try makeCatalog()
        let secret = "private-token-\(UUID().uuidString)"
        let entry = try catalog.addServer(
            name: "Local", baseURL: URL(string: "http://127.0.0.1:8080")!,
            modelID: "m", voiceID: "v", authToken: secret
        )
        defer { try? catalog.remove(id: entry.id) }

        XCTAssertEqual(try makeCatalog().authToken(for: entry.id), secret)
        let json = try String(contentsOf: sandbox.appending(path: "ApplicationSupport/voice-models.json"), encoding: .utf8)
        XCTAssertFalse(json.contains(secret))
    }

    func testServerConfigurationChangeInvalidatesItsSynthesisCacheIdentity() async throws {
        let catalog = try makeCatalog()
        let entry = try catalog.addServer(
            name: "Local", baseURL: URL(string: "http://127.0.0.1:8080")!, modelID: "model-a", voiceID: "voice-a"
        )
        let original = try await catalog.synthesisCacheIdentity(forProviderVoiceID: entry.providerVoiceID)

        try catalog.updateServer(
            id: entry.id, name: "Local", baseURL: URL(string: "http://127.0.0.1:8080")!,
            modelID: "model-b", voiceID: "voice-b"
        )

        let updated = try await catalog.synthesisCacheIdentity(forProviderVoiceID: entry.providerVoiceID)
        XCTAssertNotEqual(updated, original)
    }

    func testLinkedModelWeightChangesAtSamePathInvalidateSynthesisCacheIdentity() async throws {
        let source = try makeFishFixture()
        let catalog = try makeCatalog()
        let entry = try catalog.linkModel(at: source)
        let original = try await catalog.synthesisCacheIdentity(forProviderVoiceID: entry.providerVoiceID)

        try Data("replacement weights with a different size".utf8).write(to: source.appending(path: "model.safetensors"))

        let updated = try await catalog.synthesisCacheIdentity(forProviderVoiceID: entry.providerVoiceID)

        XCTAssertNotEqual(updated, original)
    }

    func testTamperedCatalogCannotRestoreRemoteServer() throws {
        _ = try makeCatalog()
        let remote = VoiceModelEntry(
            id: UUID(), name: "Remote", source: .loopbackServer,
            modelID: "m", voiceID: "v", serverURL: URL(string: "http://example.com:8080"),
            bookmarkData: nil, managedDirectoryName: nil
        )
        let data = try JSONEncoder().encode([remote])
        try data.write(to: sandbox.appending(path: "ApplicationSupport/voice-models.json"))

        XCTAssertThrowsError(try makeCatalog())
    }

    private func makeCatalog(trashModel: ((URL) throws -> Void)? = nil) throws -> VoiceModelCatalog {
        try VoiceModelCatalog(
            rootURL: sandbox.appending(path: "ApplicationSupport"),
            bookmarkCreationOptions: [],
            bookmarkResolutionOptions: [],
            trashModel: trashModel ?? { _ in XCTFail("Unexpected managed model Trash request") }
        )
    }

    private func makeFishFixture(named name: String = "Fish S2") throws -> URL {
        let url = sandbox.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(#"{"model_type":"fish_qwen3_omni"}"#.utf8).write(to: url.appending(path: "config.json"))
        try Data("tokenizer".utf8).write(to: url.appending(path: "tokenizer.json"))
        try Data("{}".utf8).write(to: url.appending(path: "tokenizer_config.json"))
        try Data("weights".utf8).write(to: url.appending(path: "model.safetensors"))
        try Data("codec".utf8).write(to: url.appending(path: "codec.safetensors"))
        return url
    }
}

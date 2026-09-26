import AvailPlayback
import CryptoKit
import Foundation
import Observation
import Security

enum VoiceModelSource: String, Codable, Sendable {
    case linked
    case managed
    case loopbackServer
}

struct VoiceModelEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let source: VoiceModelSource
    var modelID: String?
    var voiceID: String?
    var serverURL: URL?
    var bookmarkData: Data?
    var managedDirectoryName: String?
    var synthesisRevision: UUID? = nil
    var modelFingerprint: String? = nil

    var providerVoiceID: String { "neural:\(id.uuidString)" }
    var serverHost: String? { serverURL?.host }
    var serverPort: Int? { serverURL?.port }
}

enum VoiceModelCatalogError: LocalizedError {
    case incompatibleModel(String)
    case inaccessibleModel
    case missingEntry
    case invalidServer
    case invalidServerFields
    case confirmationRequired
    case corruptCatalog
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .incompatibleModel(let reason): "This folder is not a supported Fish Audio S2 Pro MLX model: \(reason)"
        case .inaccessibleModel: "Avail cannot access this voice model folder. Reconnect it in Voices settings."
        case .missingEntry: "This voice is no longer in the model catalog. Choose another voice."
        case .invalidServer: "Enter an HTTP server at literal 127.0.0.1 or ::1 with a port."
        case .invalidServerFields: "Enter a name, model ID, and voice ID for the local server."
        case .confirmationRequired: "Confirm moving this managed model to Trash before removing it."
        case .corruptCatalog: "The saved voice model catalog could not be read. Its files were left intact."
        case .keychain: "Avail could not update the server credential in Keychain."
        }
    }
}

@MainActor
final class VoiceModelAccessLease {
    let url: URL
    let bookmarkData: Data?
    private let securityScopeStarted: Bool

    init(url: URL, bookmarkData: Data?, securityScopeStarted: Bool) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.securityScopeStarted = securityScopeStarted
    }

    deinit {
        if securityScopeStarted {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

@MainActor
@Observable
final class VoiceModelCatalog {
    private(set) var entries: [VoiceModelEntry] = []

    private let modelsURL: URL
    private let catalogURL: URL
    private let bookmarkCreationOptions: URL.BookmarkCreationOptions
    private let bookmarkResolutionOptions: URL.BookmarkResolutionOptions
    private let keychainService: String
    private let fileManager: FileManager
    private let trashModel: (URL) throws -> Void

    init(
        rootURL: URL? = nil,
        bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope],
        bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI],
        fileManager: FileManager = .default,
        trashModel: @escaping (URL) throws -> Void = { url in
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        }
    ) throws {
        let appSupport =
            try rootURL
            ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: "Avail", directoryHint: .isDirectory)
        self.modelsURL = appSupport.appending(path: "Models", directoryHint: .isDirectory)
        self.catalogURL = appSupport.appending(path: "voice-models.json")
        self.bookmarkCreationOptions = bookmarkCreationOptions
        self.bookmarkResolutionOptions = bookmarkResolutionOptions
        let rootDigest = SHA256.hash(data: Data(appSupport.standardizedFileURL.path.utf8))
        self.keychainService = "app.avail.voice-server.\(rootDigest.map { String(format: "%02x", $0) }.joined())"
        self.fileManager = fileManager
        self.trashModel = trashModel
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: catalogURL.path) {
            do {
                entries = try JSONDecoder().decode([VoiceModelEntry].self, from: Data(contentsOf: catalogURL))
                try validateLoadedEntries()
            } catch {
                throw VoiceModelCatalogError.corruptCatalog
            }
        }
        try recoverInterruptedCopies()
    }

    @discardableResult
    func linkModel(at url: URL, name: String? = nil) throws -> VoiceModelEntry {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        try FishS2ModelFolder.validate(at: url)
        let bookmark = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let entry = VoiceModelEntry(
            id: UUID(),
            name: displayName(name, fallback: url.lastPathComponent),
            source: .linked,
            modelID: nil,
            voiceID: nil,
            serverURL: nil,
            bookmarkData: bookmark,
            managedDirectoryName: nil,
            synthesisRevision: UUID()
        )
        try add(entry)
        return entry
    }

    @discardableResult
    func reconnectLinkedModel(id: UUID, at url: URL) throws -> VoiceModelEntry {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.source == .linked }) else {
            throw VoiceModelCatalogError.missingEntry
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        try FishS2ModelFolder.validate(at: url)
        let bookmark = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var updated = entries[index]
        updated.bookmarkData = bookmark
        updated.synthesisRevision = UUID()
        try replaceEntry(at: index, with: updated)
        return updated
    }

    @discardableResult
    func copyModel(from url: URL, name: String? = nil) async throws -> VoiceModelEntry {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let directoryName = id.uuidString
        let stage = modelsURL.appending(path: ".stage-\(directoryName)", directoryHint: .isDirectory)
        let destination = modelsURL.appending(path: directoryName, directoryHint: .isDirectory)
        try await Task.detached(priority: .utility) {
            let manager = FileManager.default
            do {
                try Task.checkCancellation()
                try FishS2ModelFolder.validate(at: url)
                try Self.rejectSymbolicLinks(in: url, fileManager: manager)
                try manager.copyItem(at: url, to: stage)
                try Task.checkCancellation()
                try FishS2ModelFolder.validate(at: stage)
                try Self.rejectSymbolicLinks(in: stage, fileManager: manager)
                try manager.moveItem(at: stage, to: destination)
            } catch {
                try? manager.removeItem(at: stage)
                throw error
            }
        }.value
        let entry = VoiceModelEntry(
            id: id,
            name: displayName(name, fallback: url.lastPathComponent),
            source: .managed,
            modelID: nil,
            voiceID: nil,
            serverURL: nil,
            bookmarkData: nil,
            managedDirectoryName: directoryName,
            synthesisRevision: UUID()
        )
        do {
            try add(entry)
            return entry
        } catch {
            _ = try? await Task.detached(priority: .utility) {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: destination, resultingItemURL: &trashed)
            }.value
            throw error
        }
    }

    @discardableResult
    func addServer(
        name: String,
        baseURL: URL,
        modelID: String,
        voiceID: String,
        authToken: String? = nil
    ) throws -> VoiceModelEntry {
        let fields = try validatedServerFields(name: name, baseURL: baseURL, modelID: modelID, voiceID: voiceID)
        let entry = VoiceModelEntry(
            id: UUID(), name: fields.name, source: .loopbackServer,
            modelID: fields.modelID, voiceID: fields.voiceID, serverURL: fields.url,
            bookmarkData: nil, managedDirectoryName: nil, synthesisRevision: UUID()
        )
        if let authToken, !authToken.isEmpty { try saveToken(authToken, for: entry.id) }
        do {
            try add(entry)
        } catch {
            try? deleteToken(for: entry.id)
            throw error
        }
        return entry
    }

    func updateServer(
        id: UUID,
        name: String,
        baseURL: URL,
        modelID: String,
        voiceID: String,
        authToken: String? = nil
    ) throws {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.source == .loopbackServer }) else {
            throw VoiceModelCatalogError.missingEntry
        }
        let fields = try validatedServerFields(name: name, baseURL: baseURL, modelID: modelID, voiceID: voiceID)
        var updated = entries[index]
        updated.name = fields.name
        updated.serverURL = fields.url
        updated.modelID = fields.modelID
        updated.voiceID = fields.voiceID
        updated.synthesisRevision = UUID()
        try replaceEntry(at: index, with: updated)
        if let authToken {
            if authToken.isEmpty { try deleteToken(for: id) } else { try saveToken(authToken, for: id) }
        }
    }

    func remove(id: UUID, confirmedManagedDeletion: Bool = false) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { throw VoiceModelCatalogError.missingEntry }
        if entry.source == .managed {
            guard confirmedManagedDeletion else { throw VoiceModelCatalogError.confirmationRequired }
            guard let directoryName = entry.managedDirectoryName, directoryName == entry.id.uuidString else {
                throw VoiceModelCatalogError.corruptCatalog
            }
            let destination = modelsURL.appending(path: directoryName, directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: destination.path) {
                try trashModel(destination)
            }
        }
        let updated = entries.filter { $0.id != id }
        try persist(updated)
        entries = updated
        if entry.source == .loopbackServer { try deleteToken(for: id) }
    }

    func beginModelAccess(id: UUID) throws -> VoiceModelAccessLease {
        guard let entry = entries.first(where: { $0.id == id }) else { throw VoiceModelCatalogError.missingEntry }
        switch entry.source {
        case .loopbackServer:
            throw VoiceModelCatalogError.inaccessibleModel
        case .managed:
            guard let name = entry.managedDirectoryName, name == id.uuidString else {
                throw VoiceModelCatalogError.corruptCatalog
            }
            let url = modelsURL.appending(path: name, directoryHint: .isDirectory)
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true
            else { throw VoiceModelCatalogError.inaccessibleModel }
            let bookmark = try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return VoiceModelAccessLease(url: url, bookmarkData: bookmark, securityScopeStarted: false)
        case .linked:
            guard let bookmark = entry.bookmarkData else { throw VoiceModelCatalogError.corruptCatalog }
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            let needsScope = bookmarkResolutionOptions.contains(.withSecurityScope)
            let started = needsScope ? url.startAccessingSecurityScopedResource() : false
            guard !needsScope || started else { throw VoiceModelCatalogError.inaccessibleModel }
            var accessTransferred = false
            defer {
                if started && !accessTransferred { url.stopAccessingSecurityScopedResource() }
            }
            guard fileManager.fileExists(atPath: url.path) else {
                throw VoiceModelCatalogError.inaccessibleModel
            }
            if stale {
                let refreshed = try url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    var updated = entries[index]
                    updated.bookmarkData = refreshed
                    updated.synthesisRevision = UUID()
                    try replaceEntry(at: index, with: updated)
                }
            }
            let lease = VoiceModelAccessLease(
                url: url,
                bookmarkData: stale ? entries.first(where: { $0.id == id })?.bookmarkData : bookmark,
                securityScopeStarted: started
            )
            accessTransferred = true
            return lease
        }
    }

    func authToken(for id: UUID) throws -> String? {
        guard entries.contains(where: { $0.id == id && $0.source == .loopbackServer }) else {
            throw VoiceModelCatalogError.missingEntry
        }
        let query = tokenQuery(for: id)
        let request = query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw VoiceModelCatalogError.keychain(status)
        }
        return token
    }

    func synthesisCacheIdentity(forProviderVoiceID providerVoiceID: String) async throws -> String {
        guard providerVoiceID.hasPrefix("neural:"),
            let id = UUID(uuidString: String(providerVoiceID.dropFirst("neural:".count))),
            var entry = entries.first(where: { $0.id == id })
        else { return providerVoiceID }

        if entry.source != .loopbackServer {
            let lease = try beginModelAccess(id: id)
            let folder = lease.url
            let fingerprint = try await Task.detached(priority: .utility) {
                try FishS2ModelFolder.cacheFingerprint(at: folder)
            }.value
            if let index = entries.firstIndex(where: { $0.id == id }), entries[index].modelFingerprint != fingerprint {
                var updated = entries[index]
                updated.modelFingerprint = fingerprint
                updated.synthesisRevision = UUID()
                try replaceEntry(at: index, with: updated)
            }
            guard let refreshed = entries.first(where: { $0.id == id }) else {
                throw VoiceModelCatalogError.missingEntry
            }
            entry = refreshed
        }

        let sourceIdentity =
            entry.synthesisRevision?.uuidString
            ?? [
                entry.source.rawValue,
                entry.serverURL?.absoluteString ?? "",
                entry.modelID ?? "",
                entry.voiceID ?? "",
                entry.managedDirectoryName ?? "",
                entry.bookmarkData?.base64EncodedString() ?? "",
            ].joined(separator: "\0")
        let digest = SHA256.hash(data: Data((id.uuidString + "\0" + sourceIdentity + "\0" + (entry.modelFingerprint ?? "")).utf8))
        return "\(providerVoiceID):\(digest.map { String(format: "%02x", $0) }.joined())"
    }

    private func add(_ entry: VoiceModelEntry) throws {
        let updated = entries + [entry]
        try persist(updated)
        entries = updated
    }

    private func replaceEntry(at index: Int, with entry: VoiceModelEntry) throws {
        var updated = entries
        updated[index] = entry
        try persist(updated)
        entries = updated
    }

    private func persist(_ entries: [VoiceModelEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: catalogURL, options: .atomic)
    }

    private func validateLoadedEntries() throws {
        guard Set(entries.map(\.id)).count == entries.count else {
            throw VoiceModelCatalogError.corruptCatalog
        }
        for entry in entries {
            switch entry.source {
            case .linked:
                guard let bookmark = entry.bookmarkData, !bookmark.isEmpty else {
                    throw VoiceModelCatalogError.corruptCatalog
                }
            case .managed:
                guard entry.managedDirectoryName == entry.id.uuidString else {
                    throw VoiceModelCatalogError.corruptCatalog
                }
            case .loopbackServer:
                guard let url = entry.serverURL, let modelID = entry.modelID, let voiceID = entry.voiceID else {
                    throw VoiceModelCatalogError.corruptCatalog
                }
                let canonical = try validatedServerFields(name: entry.name, baseURL: url, modelID: modelID, voiceID: voiceID)
                guard canonical.url == url else { throw VoiceModelCatalogError.corruptCatalog }
            }
        }
    }

    private func recoverInterruptedCopies() throws {
        let referenced = Set(entries.compactMap(\.managedDirectoryName))
        for url in try fileManager.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            let name = url.lastPathComponent
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if name.hasPrefix(".stage-"), UUID(uuidString: String(name.dropFirst(7))) != nil {
                try fileManager.removeItem(at: url)
            } else if UUID(uuidString: name) != nil && !referenced.contains(name) {
                try trashModel(url)
            }
        }
    }

    private func validatedServerFields(name: String, baseURL: URL, modelID: String, voiceID: String) throws -> (name: String, url: URL, modelID: String, voiceID: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVoice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanModel.isEmpty, !cleanVoice.isEmpty else {
            throw VoiceModelCatalogError.invalidServerFields
        }
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            components.scheme == "http", components.host == "127.0.0.1" || components.host == "[::1]",
            let port = components.port, (1...65_535).contains(port),
            components.user == nil, components.password == nil,
            components.path.isEmpty || components.path == "/",
            components.query == nil, components.fragment == nil
        else { throw VoiceModelCatalogError.invalidServer }
        let host = components.host == "[::1]" ? "[::1]" : "127.0.0.1"
        return (cleanName, URL(string: "http://\(host):\(port)")!, cleanModel, cleanVoice)
    }

    private func displayName(_ proposed: String?, fallback: String) -> String {
        let clean = proposed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? fallback : clean
    }

    private func tokenQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    private func saveToken(_ token: String, for id: UUID) throws {
        let query = tokenQuery(for: id)
        let data = Data(token.utf8)
        var status = SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw VoiceModelCatalogError.keychain(status) }
    }

    private func deleteToken(for id: UUID) throws {
        let status = SecItemDelete(tokenQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VoiceModelCatalogError.keychain(status)
        }
    }

    nonisolated private static func rejectSymbolicLinks(in root: URL, fileManager: FileManager) throws {
        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
            let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
        else { throw VoiceModelCatalogError.incompatibleModel("The folder could not be inspected.") }
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else {
                throw VoiceModelCatalogError.incompatibleModel("Symbolic links are not supported in managed model copies.")
            }
        }
    }
}

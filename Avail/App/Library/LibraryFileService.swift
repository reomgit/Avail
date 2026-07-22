import CryptoKit
import Foundation

struct LibraryFileSnapshot: Sendable {
    let url: URL
    let fingerprint: String
    let resourceIdentifier: String?
    let size: Int64
    let modificationDate: Date?
}

actor LibraryFileService {
    private let fileManager: FileManager
    private let supportedExtensions = Set(["epub", "pdf"])

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fingerprint(of url: URL) throws -> String {
        guard fileManager.isReadableFile(atPath: url.path) else { throw LibraryError.sourceUnreadable }
        var hasher = SHA256()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try hashDirectory(at: url, into: &hasher)
        } else {
            try hashFile(at: url, into: &hasher)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func hashDirectory(at root: URL, into hasher: inout SHA256) throws {
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw LibraryError.sourceUnreadable
        }
        let rootPath = root.standardizedFileURL.path + "/"
        let files = enumerator.compactMap { $0 as? URL }.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }

        for file in files {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { throw LibraryError.sourceUnreadable }
            let relativePath = String(path.dropFirst(rootPath.count))
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            try hashFile(at: file, into: &hasher)
            hasher.update(data: Data([0]))
        }
    }

    private func hashFile(at url: URL, into hasher: inout SHA256) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
    }

    func importFile(from source: URL, to root: URL, fingerprint: String) throws -> LibraryFileSnapshot {
        try ensureDirectory(root)
        let rootPath = root.standardizedFileURL.path
        let sourceParent = source.deletingLastPathComponent().standardizedFileURL.path
        let destination: URL
        if rootPath == sourceParent {
            destination = source
        } else {
            destination = collisionSafeDestination(for: source.lastPathComponent, in: root)
            let temporary = root.appending(path: ".avail-import-\(UUID().uuidString).tmp")
            do {
                try fileManager.copyItem(at: source, to: temporary)
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw LibraryError.fileOperation("Avail could not copy \(source.lastPathComponent) into the library.")
            }
        }
        return try snapshot(of: destination, knownFingerprint: fingerprint)
    }

    func supportedFiles(in root: URL) throws -> [URL] {
        try ensureDirectory(root)
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func snapshot(of url: URL, knownFingerprint: String? = nil) throws -> LibraryFileSnapshot {
        let values = try url.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        return LibraryFileSnapshot(
            url: url,
            fingerprint: try knownFingerprint ?? fingerprint(of: url),
            resourceIdentifier: values.fileResourceIdentifier.map(String.init(describing:)),
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate
        )
    }

    func copyForRelocation(relativePaths: [String], from sourceRoot: URL, to destinationRoot: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: destinationRoot.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LibraryError.destinationInvalid }
        } else {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        }

        var created: [URL] = []
        do {
            for relativePath in relativePaths {
                let source = sourceRoot.appending(path: relativePath)
                let destination = destinationRoot.appending(path: relativePath)
                if fileManager.fileExists(atPath: destination.path) {
                    guard try fingerprint(of: source) == fingerprint(of: destination) else {
                        throw LibraryError.fileOperation("A different file named \(relativePath) already exists in the new library.")
                    }
                    continue
                }
                let temporary = destinationRoot.appending(path: ".avail-relocate-\(UUID().uuidString).tmp")
                try fileManager.copyItem(at: source, to: temporary)
                try fileManager.moveItem(at: temporary, to: destination)
                created.append(destination)
                guard try fingerprint(of: source) == fingerprint(of: destination) else {
                    throw LibraryError.fileOperation("Verification failed while moving \(relativePath).")
                }
            }
        } catch {
            for url in created { try? fileManager.removeItem(at: url) }
            throw error
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LibraryError.destinationInvalid }
        } else {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func collisionSafeDestination(for fileName: String, in root: URL) -> URL {
        let original = root.appending(path: fileName)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let source = URL(filePath: fileName)
        let stem = source.deletingPathExtension().lastPathComponent
        let extensionSuffix = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension)"
        var counter = 2
        while true {
            let candidate = root.appending(path: "\(stem) (\(counter))\(extensionSuffix)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}

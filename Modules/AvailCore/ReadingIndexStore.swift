import Foundation

public struct IndexedChunkPosition: Equatable, Sendable {
    public let chunk: SpeechChunk
    public let wordOffsetWithinChunk: Int
    public let globalWordOffset: Int

    public init(chunk: SpeechChunk, wordOffsetWithinChunk: Int, globalWordOffset: Int) {
        self.chunk = chunk
        self.wordOffsetWithinChunk = wordOffsetWithinChunk
        self.globalWordOffset = globalWordOffset
    }
}

public enum ReadingIndexStoreError: Error, Equatable {
    case notPrepared(UUID)
    case batchConflict(Int)
    case corruptManifest
}

public actor ReadingIndexStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    @discardableResult
    public func prepare(bookID: UUID) throws -> IndexManifest {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let directory = directoryURL(for: bookID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = manifestURL(for: bookID)

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            let manifest = IndexManifest()
            try AtomicFileWriter.write(manifest, to: manifestURL, encoder: encoder)
            return manifest
        }

        do {
            let manifest = try decoder.decode(IndexManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.schemaVersion == IndexManifest.currentSchemaVersion else {
                return try resetDerivedFiles(bookID: bookID)
            }
            return manifest
        } catch {
            return try resetDerivedFiles(bookID: bookID)
        }
    }

    public func commit(_ batch: IndexBatch, bookID: UUID) throws {
        var current = try prepare(bookID: bookID)
        let fileName = batchFileName(ordinal: batch.ordinal)
        let destination = directoryURL(for: bookID).appending(path: fileName)

        if current.batchFiles.contains(fileName) {
            let existing = try decoder.decode(IndexBatch.self, from: Data(contentsOf: destination))
            guard existing == batch else { throw ReadingIndexStoreError.batchConflict(batch.ordinal) }
            return
        }

        try AtomicFileWriter.write(batch, to: destination, encoder: encoder)
        current.batchFiles.append(fileName)
        current.indexedWordCount += batch.chunks.reduce(into: 0) { $0 += $1.wordCount }
        current.playableFrontier = batch.resumeLocator
        try AtomicFileWriter.write(current, to: manifestURL(for: bookID), encoder: encoder)
    }

    public func markComplete(bookID: UUID) throws {
        var current = try prepare(bookID: bookID)
        current.isComplete = true
        try AtomicFileWriter.write(current, to: manifestURL(for: bookID), encoder: encoder)
    }

    public func manifest(bookID: UUID) throws -> IndexManifest {
        try prepare(bookID: bookID)
    }

    public func chunks(bookID: UUID, around chunkID: UUID?, limit: Int) throws -> [SpeechChunk] {
        guard limit > 0 else { return [] }
        let allChunks = try loadBatches(bookID: bookID).flatMap(\.chunks)
        let start: Int
        if let chunkID, let index = allChunks.firstIndex(where: { $0.id == chunkID }) {
            start = index
        } else {
            start = 0
        }
        guard start < allChunks.count else { return [] }
        return Array(allChunks[start..<min(start + limit, allChunks.count)])
    }

    public func sections(bookID: UUID) throws -> [ReadingSection] {
        try loadBatches(bookID: bookID).flatMap(\.sections)
    }

    public func position(bookID: UUID, normalizedWordOffset requestedOffset: Int) throws -> IndexedChunkPosition? {
        let chunks = try loadBatches(bookID: bookID).flatMap(\.chunks)
        guard !chunks.isEmpty else { return nil }

        let offset = max(0, requestedOffset)
        var globalStart = 0
        for chunk in chunks {
            let upperBound = globalStart + chunk.wordCount
            if offset < upperBound || chunk.id == chunks.last?.id {
                return IndexedChunkPosition(
                    chunk: chunk,
                    wordOffsetWithinChunk: min(max(0, offset - globalStart), max(0, chunk.wordCount - 1)),
                    globalWordOffset: globalStart
                )
            }
            globalStart = upperBound
        }
        return nil
    }

    @discardableResult
    public func recover(bookID: UUID) throws -> IndexManifest {
        var current = try prepare(bookID: bookID)
        let directory = directoryURL(for: bookID)
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let committed = Set(current.batchFiles)
        for entry in entries {
            if entry.pathExtension == "tmp"
                || (entry.lastPathComponent.hasPrefix("batch-") && !committed.contains(entry.lastPathComponent))
            {
                try fileManager.removeItem(at: entry)
            }
        }

        let existingFiles = current.batchFiles.filter {
            fileManager.fileExists(atPath: directory.appending(path: $0).path)
        }
        if existingFiles != current.batchFiles {
            current.batchFiles = existingFiles
            let batches = try existingFiles.map { fileName in
                try decoder.decode(IndexBatch.self, from: Data(contentsOf: directory.appending(path: fileName)))
            }
            current.indexedWordCount = batches.flatMap(\.chunks).reduce(into: 0) { $0 += $1.wordCount }
            current.playableFrontier = batches.last?.resumeLocator
            current.isComplete = false
            try AtomicFileWriter.write(current, to: manifestURL(for: bookID), encoder: encoder)
        }
        return current
    }

    public func discard(bookID: UUID) throws {
        let directory = directoryURL(for: bookID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func loadBatches(bookID: UUID) throws -> [IndexBatch] {
        let current = try prepare(bookID: bookID)
        let directory = directoryURL(for: bookID)
        return try current.batchFiles.map { fileName in
            try decoder.decode(IndexBatch.self, from: Data(contentsOf: directory.appending(path: fileName)))
        }
    }

    private func resetDerivedFiles(bookID: UUID) throws -> IndexManifest {
        let directory = directoryURL(for: bookID)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = IndexManifest()
        try AtomicFileWriter.write(manifest, to: manifestURL(for: bookID), encoder: encoder)
        return manifest
    }

    private func directoryURL(for bookID: UUID) -> URL {
        rootURL.appending(path: bookID.uuidString, directoryHint: .isDirectory)
    }

    private func manifestURL(for bookID: UUID) -> URL {
        directoryURL(for: bookID).appending(path: "manifest.json")
    }

    private func batchFileName(ordinal: Int) -> String {
        String(format: "batch-%06d.json", ordinal)
    }
}

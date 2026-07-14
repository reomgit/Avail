import AvailCore
import Foundation
import SwiftData

enum LibraryImportResult: Equatable {
    case created(UUID)
    case existing(UUID)
}

enum LibraryRemovalMode {
    case recordOnly
    case moveFileToTrash
}

@MainActor
final class LibraryStore {
    typealias TrashHandler = @MainActor (URL) throws -> Void

    private let context: ModelContext
    private let locationStore: LibraryLocationStore
    private let fileService: LibraryFileService
    private let trashHandler: TrashHandler

    init(
        modelContainer: ModelContainer,
        locationStore: LibraryLocationStore,
        fileService: LibraryFileService = LibraryFileService(),
        trashHandler: @escaping TrashHandler = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.context = ModelContext(modelContainer)
        self.locationStore = locationStore
        self.fileService = fileService
        self.trashHandler = trashHandler
    }

    func books() throws -> [LibraryBookRecord] {
        try context.fetch(FetchDescriptor<LibraryBookRecord>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func book(id: UUID) throws -> LibraryBookRecord? {
        try books().first(where: { $0.id == id })
    }

    func importBook(from source: URL) async throws -> LibraryImportResult {
        let format = try format(for: source)
        let access = try locationStore.beginAccess()
        let root = access.url
        let fingerprint = try await fileService.fingerprint(of: source)
        if let existing = try books().first(where: { $0.fingerprint == fingerprint }) {
            return .existing(existing.id)
        }

        let snapshot = try await fileService.importFile(from: source, to: root, fingerprint: fingerprint)
        let relativePath = snapshot.url.lastPathComponent
        let record = LibraryBookRecord(
            fingerprint: snapshot.fingerprint,
            relativePath: relativePath,
            title: snapshot.url.deletingPathExtension().lastPathComponent,
            format: format,
            state: .indexing,
            fileResourceIdentifier: snapshot.resourceIdentifier,
            fileSize: snapshot.size,
            fileModificationDate: snapshot.modificationDate
        )
        context.insert(record)
        try context.save()
        return .created(record.id)
    }

    func rescan() async throws {
        let access = try locationStore.beginAccess()
        let root = access.url
        let files = try await fileService.supportedFiles(in: root)
        let records = try books()
        var seenIDs = Set<UUID>()

        for file in files {
            let relativePath = file.lastPathComponent
            if let record = records.first(where: { $0.relativePath == relativePath }) {
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                record.fileSize = Int64(values.fileSize ?? 0)
                record.fileModificationDate = values.contentModificationDate
                if record.state == .missing {
                    record.state = record.isIndexComplete ? .ready : .indexing
                }
                record.updatedAt = Date()
                seenIDs.insert(record.id)
                continue
            }

            let snapshot = try await fileService.snapshot(of: file)
            if let renamed = records.first(where: { $0.fingerprint == snapshot.fingerprint && !seenIDs.contains($0.id) }) {
                renamed.relativePath = relativePath
                renamed.fileResourceIdentifier = snapshot.resourceIdentifier
                renamed.fileSize = snapshot.size
                renamed.fileModificationDate = snapshot.modificationDate
                renamed.state = renamed.isIndexComplete ? .ready : .indexing
                renamed.updatedAt = Date()
                seenIDs.insert(renamed.id)
            } else if records.contains(where: { $0.fingerprint == snapshot.fingerprint }) {
                continue
            } else {
                let record = LibraryBookRecord(
                    fingerprint: snapshot.fingerprint,
                    relativePath: relativePath,
                    title: file.deletingPathExtension().lastPathComponent,
                    format: try format(for: file),
                    state: .indexing,
                    fileResourceIdentifier: snapshot.resourceIdentifier,
                    fileSize: snapshot.size,
                    fileModificationDate: snapshot.modificationDate
                )
                context.insert(record)
                seenIDs.insert(record.id)
            }
        }

        for record in records where !seenIDs.contains(record.id) {
            record.state = .missing
            record.updatedAt = Date()
        }
        try context.save()
    }

    func remove(bookID: UUID, mode: LibraryRemovalMode) async throws {
        guard let record = try book(id: bookID) else { throw LibraryError.missingRecord }
        if mode == .moveFileToTrash {
            let access = try locationStore.beginAccess()
            try trashHandler(access.url.appending(path: record.relativePath))
        }
        context.delete(record)
        try context.save()
    }

    func relocate(to destination: URL) async throws {
        let access = try locationStore.beginAccess()
        let sourceRoot = access.url
        let records = try books().filter { $0.state != .missing }
        try await fileService.copyForRelocation(
            relativePaths: records.map(\.relativePath),
            from: sourceRoot,
            to: destination
        )
        try locationStore.select(destination)
        for record in records {
            let source = sourceRoot.appending(path: record.relativePath)
            if FileManager.default.fileExists(atPath: source.path) {
                try? trashHandler(source)
            }
        }
    }

    private func format(for url: URL) throws -> BookFormat {
        switch url.pathExtension.lowercased() {
        case "epub": .epub
        case "pdf": .pdf
        default: throw LibraryError.unsupportedFormat
        }
    }
}

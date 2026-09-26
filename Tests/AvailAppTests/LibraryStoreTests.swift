import AvailCore
import Foundation
import SwiftData
import XCTest
@testable import AvailApp

@MainActor
final class LibraryStoreTests: XCTestCase {
    nonisolated(unsafe) private var sandbox: URL!
    nonisolated(unsafe) private var libraryURL: URL!
    nonisolated(unsafe) private var sourceURL: URL!
    private var defaults: UserDefaults!
    private var locationStore: LibraryLocationStore!
    private var container: ModelContainer!
    private var artworkStore: ArtworkStore!
    private var store: LibraryStore!
    private var trashedURLs: [URL] = []

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "AvailLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        libraryURL = sandbox.appending(path: "Library", directoryHint: .isDirectory)
        sourceURL = sandbox.appending(path: "Sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    func testImportCopiesBookAndExactDuplicateFocusesExistingRecord() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Book.epub")
        try Data("same-content".utf8).write(to: source)

        let created = try await store.importBook(from: source)
        let duplicate = try await store.importBook(from: source)
        let books = try store.books()

        guard case let .created(createdID) = created else { return XCTFail("Expected a new record") }
        XCTAssertEqual(duplicate, .existing(createdID))
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].relativePath, "Book.epub")
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.appending(path: "Book.epub").path))
    }

    func testGeneratedAudioResumeSurvivesLibraryPositionSave() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Resume.epub")
        try Data("synthetic book".utf8).write(to: source)
        guard case let .created(bookID) = try await store.importBook(from: source) else {
            return XCTFail("Expected a new record")
        }
        let point = AudioResumePoint(
            clipKey: "current-phrase", phraseStartUTF16Offset: 8,
            phraseEndUTF16Offset: 33, frameOffset: 12_345, sampleRate: 24_000
        )
        let position = ReadingPosition(
            bookID: bookID, sectionID: UUID(), chunkID: UUID(),
            utf16Offset: 8, normalizedWordOffset: 15,
            updatedAt: Date(), audioResume: point
        )

        try store.savePlaybackPosition(position)

        XCTAssertEqual(try store.book(id: bookID)?.readingPosition()?.audioResume, point)
    }

    func testImportCopiesUnpackedEPUBPackage() async throws {
        try prepareStore()
        let source = try makeUnpackedEPUB(named: "Package.epub", in: sourceURL)

        _ = try await store.importBook(from: source)

        let destination = libraryURL.appending(path: "Package.epub", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appending(path: "mimetype").path))
        XCTAssertEqual(try store.books().map(\.relativePath), ["Package.epub"])
    }

    func testNameCollisionUsesFinderStyleSuffix() async throws {
        try prepareStore()
        let firstFolder = sourceURL.appending(path: "One", directoryHint: .isDirectory)
        let secondFolder = sourceURL.appending(path: "Two", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = firstFolder.appending(path: "Book.pdf")
        let second = secondFolder.appending(path: "Book.pdf")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        _ = try await store.importBook(from: first)
        _ = try await store.importBook(from: second)

        XCTAssertEqual(Set(try store.books().map(\.relativePath)), ["Book.pdf", "Book (2).pdf"])
    }

    func testRescanReconcilesExternalRenameByFingerprint() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Original.epub")
        try Data("rename-me".utf8).write(to: source)
        guard case let .created(bookID) = try await store.importBook(from: source) else {
            return XCTFail("Expected a new record")
        }
        try FileManager.default.moveItem(
            at: libraryURL.appending(path: "Original.epub"),
            to: libraryURL.appending(path: "Renamed.epub")
        )

        try await store.rescan()

        XCTAssertEqual(try store.books().count, 1)
        XCTAssertEqual(try store.book(id: bookID)?.relativePath, "Renamed.epub")
    }

    func testRescanEnrollsExternalBookAndMarksDeletionMissing() async throws {
        try prepareStore()
        let external = libraryURL.appending(path: "Added.pdf")
        try Data("external-book".utf8).write(to: external)

        try await store.rescan()
        let enrolled = try XCTUnwrap(store.books().first)
        XCTAssertEqual(enrolled.state, .indexing)

        try FileManager.default.removeItem(at: external)
        try await store.rescan()
        XCTAssertEqual(try store.book(id: enrolled.id)?.state, .missing)
    }

    func testRescanEnrollsExternalUnpackedEPUBPackage() async throws {
        try prepareStore()
        _ = try makeUnpackedEPUB(named: "External.epub", in: libraryURL)

        try await store.rescan()

        let enrolled = try XCTUnwrap(store.books().first)
        XCTAssertEqual(enrolled.relativePath, "External.epub")
        XCTAssertEqual(enrolled.format, .epub)
        XCTAssertEqual(enrolled.state, .indexing)
    }

    func testRemoveRecordOnlyLeavesFileAndTrashModeDelegatesFile() async throws {
        try prepareStore()
        let first = sourceURL.appending(path: "Keep.epub")
        let second = sourceURL.appending(path: "Trash.epub")
        try Data("keep".utf8).write(to: first)
        try Data("trash".utf8).write(to: second)
        guard case let .created(keepID) = try await store.importBook(from: first),
            case let .created(trashID) = try await store.importBook(from: second)
        else {
            return XCTFail("Expected records")
        }

        try await store.remove(bookID: keepID, mode: .recordOnly)
        try await store.remove(bookID: trashID, mode: .moveFileToTrash)

        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.appending(path: "Keep.epub").path))
        XCTAssertEqual(trashedURLs.map(\.lastPathComponent), ["Trash.epub"])
        XCTAssertTrue(try store.books().isEmpty)
    }

    func testMetadataPersistsValidCoverArtwork() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Cover.epub")
        try Data("book".utf8).write(to: source)
        guard case let .created(bookID) = try await store.importBook(from: source) else {
            return XCTFail("Expected a new record")
        }

        try await store.applyMetadata(
            BookMetadata(title: "Cover Book", coverData: Self.validPNG),
            bookID: bookID
        )

        let relativePath = try XCTUnwrap(store.book(id: bookID)?.coverRelativePath)
        let fileURL = try XCTUnwrap(artworkStore.fileURL(for: relativePath))
        XCTAssertEqual(try Data(contentsOf: fileURL), Self.validPNG)
    }

    func testRemovingBookDeletesDerivedArtwork() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Cover.epub")
        try Data("book".utf8).write(to: source)
        guard case let .created(bookID) = try await store.importBook(from: source) else {
            return XCTFail("Expected a new record")
        }
        try await store.applyMetadata(
            BookMetadata(title: "Cover Book", coverData: Self.validPNG),
            bookID: bookID
        )
        let relativePath = try XCTUnwrap(store.book(id: bookID)?.coverRelativePath)
        let fileURL = try XCTUnwrap(artworkStore.fileURL(for: relativePath))

        try await store.remove(bookID: bookID, mode: .recordOnly)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFailedRelocationPreservesOriginalBookmarkAndFiles() async throws {
        try prepareStore()
        let source = sourceURL.appending(path: "Book.epub")
        try Data("relocate".utf8).write(to: source)
        _ = try await store.importBook(from: source)
        let invalidDestination = sandbox.appending(path: "NotAFolder")
        try Data("file".utf8).write(to: invalidDestination)

        do {
            try await store.relocate(to: invalidDestination)
            XCTFail("Expected relocation failure")
        } catch {
            XCTAssertEqual(try locationStore.resolve()?.standardizedFileURL, libraryURL.standardizedFileURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.appending(path: "Book.epub").path))
        }
    }

    func testExistingBookmarkKeyReopensTheSelectedLibrary() throws {
        let defaults = UserDefaults(suiteName: "AvailBookmarkCompatibility-\(UUID().uuidString)")!
        let original = LibraryLocationStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: []
        )
        try original.select(libraryURL)

        let reopened = LibraryLocationStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: []
        )

        XCTAssertNotNil(defaults.data(forKey: "librarySecurityScopedBookmark"))
        XCTAssertEqual(
            try reopened.resolve()?.standardizedFileURL,
            libraryURL.standardizedFileURL
        )
    }

    func testExistingSwiftDataRecordReopensWithoutMigration() throws {
        let storeURL = sandbox.appending(path: "ExistingLibrary.store")
        let bookID = UUID()

        do {
            let existingContainer = try ModelContainer(
                for: LibraryBookRecord.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let context = ModelContext(existingContainer)
            context.insert(
                LibraryBookRecord(
                    id: bookID,
                    fingerprint: "existing-record",
                    relativePath: "Existing.epub",
                    title: "Existing Library Book",
                    format: .epub,
                    state: .ready
                )
            )
            try context.save()
        }

        let reopenedContainer = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let records = try ModelContext(reopenedContainer).fetch(
            FetchDescriptor<LibraryBookRecord>()
        )

        XCTAssertEqual(records.map(\.id), [bookID])
        XCTAssertEqual(records.first?.title, "Existing Library Book")
    }

    private func prepareStore() throws {
        trashedURLs = []
        defaults = UserDefaults(suiteName: "AvailLibraryTests-\(UUID().uuidString)")!
        locationStore = LibraryLocationStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: []
        )
        try locationStore.select(libraryURL)
        container = try ModelContainer(
            for: LibraryBookRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        artworkStore = ArtworkStore(rootURL: sandbox.appending(path: "Artwork", directoryHint: .isDirectory))
        store = LibraryStore(
            modelContainer: container,
            locationStore: locationStore,
            artworkStore: artworkStore,
            trashHandler: { [weak self] url in self?.trashedURLs.append(url) }
        )
    }

    private func makeUnpackedEPUB(named name: String, in parent: URL) throws -> URL {
        let package = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: package.appending(path: "mimetype"))
        return package
    }

    private static let validPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}

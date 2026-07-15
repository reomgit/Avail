import AvailCore
import AvailPlayback
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppEnvironment {
    enum LaunchState: Equatable {
        case needsLibraryLocation
        case loading
        case ready
        case failed(String)
    }

    var launchState: LaunchState
    var selectedBookID: UUID?
    var lastActionError: String?

    let modelContainer: ModelContainer
    let locationStore: LibraryLocationStore
    private(set) var libraryStore: LibraryStore?
    private(set) var indexStore: ReadingIndexStore?
    private(set) var indexingCoordinator: IndexingCoordinator?
    private(set) var playbackCoordinator: PlaybackCoordinator?

    init(
        launchState requestedLaunchState: LaunchState? = nil,
        defaults: UserDefaults = .standard,
        inMemory: Bool = false
    ) {
        let container: ModelContainer
        var storageFailure: String?
        do {
            container = try ModelContainer(
                for: LibraryBookRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            storageFailure = "Avail could not open its library database."
            container = try! ModelContainer(
                for: LibraryBookRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        modelContainer = container
        locationStore = LibraryLocationStore(
            defaults: defaults,
            creationOptions: inMemory ? [] : [.withSecurityScope],
            resolutionOptions: inMemory ? [] : [.withSecurityScope, .withoutUI]
        )

        let supportRoot = Self.applicationSupportRootURL(inMemory: inMemory)
        let artworkStore = ArtworkStore(
            rootURL: supportRoot.appending(path: "Artwork", directoryHint: .isDirectory)
        )
        let library = LibraryStore(
            modelContainer: container,
            locationStore: locationStore,
            artworkStore: artworkStore
        )
        let indexes = ReadingIndexStore(
            rootURL: supportRoot.appending(path: "ReadingIndexes", directoryHint: .isDirectory)
        )
        let indexing = IndexingCoordinator(libraryStore: library, indexStore: indexes)
        let playback = PlaybackCoordinator(
            engine: SystemNarrationEngine(),
            indexStore: indexes,
            libraryStore: library,
            indexingCoordinator: indexing
        )
        libraryStore = library
        indexStore = indexes
        indexingCoordinator = indexing
        playbackCoordinator = playback

        if let requestedLaunchState {
            launchState = requestedLaunchState
        } else if let storageFailure {
            launchState = .failed(storageFailure)
        } else {
            do {
                launchState = try locationStore.resolve() == nil ? .needsLibraryLocation : .ready
            } catch {
                launchState = .failed("Reconnect your library folder to continue.")
            }
        }
    }

    static func bootstrapForTesting() -> AppEnvironment {
        AppEnvironment(
            launchState: .needsLibraryLocation,
            defaults: UserDefaults(suiteName: "AvailEnvironmentTests-\(UUID().uuidString)")!,
            inMemory: true
        )
    }

    func selectLibraryLocation(_ url: URL) async {
        launchState = .loading
        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            try locationStore.select(url)
            try await libraryStore?.rescan()
            try startPendingIndexes()
            launchState = .ready
        } catch {
            launchState = .failed("Avail could not use that folder. Choose it again to reconnect.")
        }
    }

    func importBooks(from urls: [URL]) async {
        guard launchState == .ready, let libraryStore else { return }
        lastActionError = nil
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await libraryStore.importBook(from: url)
                switch result {
                case let .created(bookID):
                    selectedBookID = bookID
                    indexingCoordinator?.start(bookID: bookID)
                case let .existing(bookID):
                    selectedBookID = bookID
                }
            } catch {
                lastActionError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func rescanLibrary() async {
        do {
            try await libraryStore?.rescan()
            try startPendingIndexes()
        } catch {
            lastActionError = "The library folder could not be refreshed."
        }
    }

    private func startPendingIndexes() throws {
        let books = try libraryStore?.books() ?? []
        for book in books where book.state == .indexing && !book.isIndexComplete {
            indexingCoordinator?.startIfNeeded(bookID: book.id)
        }
    }

    private static func applicationSupportRootURL(inMemory: Bool) -> URL {
        if inMemory {
            return FileManager.default.temporaryDirectory
                .appending(path: "AvailEnvironment-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Avail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

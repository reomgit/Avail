import AvailCore
import AvailPlayback
@preconcurrency import AVFAudio
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
    private(set) var voiceCatalogError: String?
    private(set) var voiceModelCatalog: VoiceModelCatalog?
    private var neuralNarrationEngine: CompositeNarrationEngine?
    private var voicePreviewPlayer: AVAudioPlayer?
    var supportsLocalNeuralNarration: Bool {
        #if arch(arm64)
            true
        #else
            false
        #endif
    }

    let modelContainer: ModelContainer
    let locationStore: LibraryLocationStore
    private(set) var libraryStore: LibraryStore?
    private(set) var indexStore: ReadingIndexStore?
    private(set) var indexingCoordinator: IndexingCoordinator?
    private(set) var playbackCoordinator: PlaybackCoordinator?
    #if DEBUG
        private var isUITestingFixture = false
        private var didPrepareUITestingIndexes = false
    #endif

    init(
        launchState requestedLaunchState: LaunchState? = nil,
        defaults: UserDefaults = .standard,
        inMemory: Bool = false,
        narrationEngine: (any NarrationEngine)? = nil,
        nowPlayingController: (any NowPlayingControlling)? = nil
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
        let catalog: VoiceModelCatalog?
        do {
            catalog = try VoiceModelCatalog(
                rootURL: supportRoot,
                bookmarkCreationOptions: inMemory ? [] : [.withSecurityScope],
                bookmarkResolutionOptions: inMemory ? [] : [.withSecurityScope, .withoutUI]
            )
        } catch {
            catalog = nil
            voiceCatalogError = error.localizedDescription
        }
        voiceModelCatalog = catalog
        let neuralEngine = catalog.map {
            CompositeNarrationEngine(
                catalog: $0,
                cacheURL: supportRoot.appending(path: "NarrationAudio", directoryHint: .isDirectory)
            )
        }
        neuralNarrationEngine = neuralEngine
        let playback = PlaybackCoordinator(
            engine: narrationEngine ?? neuralEngine ?? SystemNarrationEngine(),
            indexStore: indexes,
            libraryStore: library,
            indexingCoordinator: indexing,
            nowPlaying: nowPlayingController ?? NowPlayingController()
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

    func previewVoice(id: String) async throws {
        guard supportsLocalNeuralNarration else { throw NeuralHelperClientError.unsupportedMac }
        guard let neuralNarrationEngine else { throw VoiceModelCatalogError.missingEntry }
        let audio = try await neuralNarrationEngine.synthesizePreview(
            voiceID: id,
            text: "This is a short local voice preview from Avail."
        )
        let player = try AVAudioPlayer(data: audio.wavData)
        player.prepareToPlay()
        guard player.play() else { throw LocalSpeechServerError.invalidAudio }
        voicePreviewPlayer = player
    }

    static func bootstrapForTesting(
        narrationEngine: (any NarrationEngine)? = nil,
        nowPlayingController: (any NowPlayingControlling)? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            launchState: .needsLibraryLocation,
            defaults: UserDefaults(suiteName: "AvailEnvironmentTests-\(UUID().uuidString)")!,
            inMemory: true,
            narrationEngine: narrationEngine,
            nowPlayingController: nowPlayingController
        )
    }

    #if DEBUG
        static func uiTestingFixture() -> AppEnvironment {
            let defaults = UserDefaults(suiteName: "AvailUITests-\(UUID().uuidString)")!
            let environment = AppEnvironment(
                launchState: .ready,
                defaults: defaults,
                inMemory: true
            )
            environment.isUITestingFixture = true
            environment.seedUITestingLibrary()
            return environment
        }

        func prepareUITestingFixtureIfNeeded() async {
            guard isUITestingFixture,
                !didPrepareUITestingIndexes,
                let indexStore
            else { return }
            didPrepareUITestingIndexes = true

            for bookID in [Self.uiTestPrimaryBookID, Self.uiTestSecondaryBookID] {
                let content = Self.uiTestReadingContent(bookID: bookID)
                do {
                    try await indexStore.commit(
                        IndexBatch(
                            ordinal: 0,
                            sections: content.sections,
                            chunks: content.chunks,
                            resumeLocator: content.sections.last?.locator ?? .pdf(pageIndex: 0)
                        ),
                        bookID: bookID
                    )
                    try await indexStore.markComplete(bookID: bookID)
                } catch {
                    lastActionError = "The UI test reading fixture could not be prepared."
                }
            }
        }

        private func seedUITestingLibrary() {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "AvailUITestLibrary-\(UUID().uuidString)", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? locationStore.select(root)

            let primary = LibraryBookRecord(
                id: Self.uiTestPrimaryBookID,
                fingerprint: "ui-fixture-primary",
                relativePath: "The Art of Listening.epub",
                title: "The Art of Listening",
                author: "Mara Ellis",
                format: .epub,
                state: .ready
            )
            let primaryContent = Self.uiTestReadingContent(bookID: primary.id)
            primary.indexedWordCount = primaryContent.chunks.reduce(0) { $0 + $1.wordCount }
            primary.isIndexComplete = true
            primary.currentSectionID = primaryContent.sections.first?.id
            primary.currentChunkID = primaryContent.chunks.first?.id
            primary.normalizedWordOffset = 180
            primary.positionUpdatedAt = Date(timeIntervalSince1970: 200)

            let secondary = LibraryBookRecord(
                id: Self.uiTestSecondaryBookID,
                fingerprint: "ui-fixture-secondary",
                relativePath: "Designing with Clarity.pdf",
                title: "Designing with Clarity",
                author: "Noah Chen",
                format: .pdf,
                state: .ready
            )
            let secondaryContent = Self.uiTestReadingContent(bookID: secondary.id)
            secondary.indexedWordCount = secondaryContent.chunks.reduce(0) { $0 + $1.wordCount }
            secondary.isIndexComplete = true

            let preparing = LibraryBookRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                fingerprint: "ui-fixture-preparing",
                relativePath: "Preparing Sample.epub",
                title: "Preparing Sample",
                author: "Local Fixture",
                format: .epub,
                state: .indexing
            )
            preparing.indexedWordCount = 120

            for record in [primary, secondary, preparing] {
                let fileURL = root.appending(path: record.relativePath)
                try? Data(record.title.utf8).write(to: fileURL, options: .atomic)
            }

            let context = ModelContext(modelContainer)
            context.insert(primary)
            context.insert(secondary)
            context.insert(preparing)
            try? context.save()
        }

        private static let uiTestPrimaryBookID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000101"
        )!
        private static let uiTestSecondaryBookID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000102"
        )!

        private static func uiTestReadingContent(
            bookID: UUID
        ) -> (sections: [ReadingSection], chunks: [SpeechChunk]) {
            let titles = ["A Quiet Beginning", "Listening with Intention"]
            var sections: [ReadingSection] = []
            var chunks: [SpeechChunk] = []

            for (ordinal, title) in titles.enumerated() {
                let locator = SourceLocator.pdf(pageIndex: ordinal)
                let sectionID = StableIdentifier.make(
                    bookID: bookID,
                    kind: "section",
                    locator: locator,
                    ordinal: ordinal
                )
                let text = Array(repeating: "A calm local passage for listening.", count: 90)
                    .joined(separator: " ")
                let chunk = SpeechChunk(
                    id: StableIdentifier.make(
                        sectionID: sectionID,
                        kind: "chunk",
                        locator: locator,
                        ordinal: ordinal
                    ),
                    sectionID: sectionID,
                    ordinal: ordinal,
                    text: text,
                    wordCount: 540,
                    locator: locator,
                    sourceRange: SourceTextRange(
                        utf16Location: 0,
                        utf16Length: text.utf16.count
                    )
                )
                chunks.append(chunk)
                sections.append(
                    ReadingSection(
                        id: sectionID,
                        ordinal: ordinal,
                        title: title,
                        locator: locator,
                        chunkIDs: [chunk.id]
                    )
                )
            }
            return (sections, chunks)
        }
    #endif

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

    func removeBook(bookID: UUID, mode: LibraryRemovalMode) async throws {
        guard let libraryStore, let indexStore else { throw LibraryError.missingRecord }
        indexingCoordinator?.cancel(bookID: bookID)
        playbackCoordinator?.clearSession(for: bookID)
        try await libraryStore.remove(bookID: bookID, mode: mode)
        try await indexStore.discard(bookID: bookID)
        if selectedBookID == bookID { selectedBookID = nil }
    }

    func rescanLibrary() async {
        #if DEBUG
            if isUITestingFixture { return }
        #endif
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

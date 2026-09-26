import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \LibraryBookRecord.createdAt) private var books: [LibraryBookRecord]
    @State private var model = LibraryViewModel()

    private var displayedBooks: [LibraryBookRecord] { model.filteredBooks(books) }
    private var selectedBook: LibraryBookRecord? {
        books.first { $0.id == model.selectedBookID }
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            LibrarySidebar(
                selection: $model.collection,
                bookCount: books.count,
                preparingCount: books.filter {
                    $0.state == .copying || $0.state == .indexing
                }.count,
                hasContinueListening: model.continueListeningBookID(in: books) != nil
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            NavigationStack(path: $model.path) {
                LibraryGridView(
                    books: displayedBooks,
                    openBook: openBook,
                    canPlay: model.canPlay,
                    play: play,
                    openZen: openZen,
                    artworkURL: artworkURL
                )
                .navigationTitle(collectionTitle)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    persistentPlayerSurface
                }
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case let .book(bookID):
                        BookDetailView(bookID: bookID)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                persistentPlayerSurface
                            }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search books")
        .toolbar {
            LibraryToolbar(
                importBooks: { model.isImporting = true },
                refreshLibrary: {
                    Task { await environment.rescanLibrary() }
                }
            )
        }
        .focusedSceneValue(\.libraryCommandActions, commandActions)
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: BookImportContentTypes.all,
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await environment.importBooks(from: urls) }
        }
        .alert("Action Failed", isPresented: actionErrorIsPresented) {
            Button("OK") { environment.lastActionError = nil }
        } message: {
            Text(environment.lastActionError ?? "The action could not be completed.")
        }
        .onChange(of: model.collection) { _, newCollection in
            model.selectCollection(newCollection)
            environment.selectedBookID = nil
        }
        .onChange(of: model.path) { _, path in
            if path.isEmpty {
                model.selectedBookID = nil
                environment.selectedBookID = nil
            }
        }
        .onAppear {
            if let selectedBookID = environment.selectedBookID,
                books.contains(where: { $0.id == selectedBookID })
            {
                model.openBook(selectedBookID)
            }
        }
        .task {
            await environment.rescanLibrary()
        }
    }

    private var persistentPlayer: some View {
        let context = persistentPlayerContext
        return FloatingPlaybackBar(
            context: context,
            artworkURL: context.book.flatMap(artworkURL),
            currentWordOffset: playerWordOffset(context),
            previousChapter: {
                Task { await environment.playbackCoordinator?.previousChapter() }
            },
            skipBackward: {
                Task { await environment.playbackCoordinator?.seek(by: -15) }
            },
            togglePlayback: {
                togglePlayback(context)
            },
            skipForward: {
                Task { await environment.playbackCoordinator?.seek(by: 15) }
            },
            nextChapter: {
                Task { await environment.playbackCoordinator?.nextChapter() }
            },
            seek: { target in
                Task {
                    await environment.playbackCoordinator?.seek(
                        toNormalizedWordOffset: target
                    )
                }
            },
            openZen: {
                if let book = context.book { openZen(book) }
            }
        )
    }

    private var persistentPlayerSurface: some View {
        persistentPlayer
            .frame(maxWidth: 1_060)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("persistent-player-shell")
    }

    private var persistentPlayerContext: PersistentPlayerContext {
        guard let playback = environment.playbackCoordinator else {
            return PersistentPlayerContext.make(
                books: books,
                currentBookID: nil,
                state: .stopped,
                chapterTitle: nil
            )
        }
        return PersistentPlayerContext.make(
            books: books,
            currentBookID: playback.currentBookID,
            state: playback.state,
            chapterTitle: playback.currentChapterTitle
        )
    }

    private var collectionTitle: String {
        switch model.collection {
        case .allBooks: "All Books"
        case .continueListening: "Continue Listening"
        case .preparing: "Preparing"
        }
    }

    private var commandActions: LibraryCommandActions {
        LibraryCommandActions(
            importBooks: { model.isImporting = true },
            togglePlayback: {
                guard let selectedBook else { return }
                togglePlayback(for: selectedBook)
            },
            openZen: {
                if let selectedBook { openZen(selectedBook) }
            },
            canPlay: model.canPlay(selectedBook),
            canOpenZen: model.canPlay(selectedBook)
        )
    }

    private var actionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { environment.lastActionError != nil },
            set: { if !$0 { environment.lastActionError = nil } }
        )
    }

    private func openBook(_ book: LibraryBookRecord) {
        model.openBook(book.id)
        environment.selectedBookID = book.id
    }

    private func play(_ book: LibraryBookRecord) {
        Task { await environment.playbackCoordinator?.play(bookID: book.id) }
    }

    private func togglePlayback(_ context: PersistentPlayerContext) {
        guard let book = context.book else { return }
        switch context.mode {
        case .empty:
            return
        case .resumable:
            play(book)
        case .active:
            togglePlayback(for: book)
        }
    }

    private func togglePlayback(for book: LibraryBookRecord) {
        guard let playback = environment.playbackCoordinator else { return }
        if playback.currentBookID != book.id {
            Task { await playback.play(bookID: book.id) }
        } else {
            switch PlaybackBarPresentation.toggleAction(for: playback.state) {
            case .pause:
                playback.pause()
            case .resume:
                playback.resume()
            case .play:
                Task { await playback.play(bookID: book.id) }
            case .none:
                break
            }
        }
    }

    private func playerWordOffset(_ context: PersistentPlayerContext) -> Int {
        switch context.mode {
        case .active:
            environment.playbackCoordinator?.currentNormalizedWordOffset ?? 0
        case .resumable:
            context.book?.normalizedWordOffset ?? 0
        case .empty:
            0
        }
    }

    private func artworkURL(for book: LibraryBookRecord) -> URL? {
        environment.libraryStore?.artworkURL(for: book)
    }

    private func openZen(_ book: LibraryBookRecord) {
        openWindow(value: book.id)
    }
}

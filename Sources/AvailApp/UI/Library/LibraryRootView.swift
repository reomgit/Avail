import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \LibraryBookRecord.createdAt) private var books: [LibraryBookRecord]
    @State private var model = LibraryViewModel()

    private var displayedBooks: [LibraryBookRecord] { model.filteredBooks(books) }
    private var selectedBook: LibraryBookRecord? {
        books.first { $0.id == model.selectedBookID }
    }

    var body: some View {
        @Bindable var model = model
        let playerContext = activePlaybackContext

        NavigationSplitView {
            LibrarySidebar(
                selection: $model.collection,
                bookCount: books.count,
                preparingCount: books.filter { $0.state == .copying || $0.state == .indexing }.count,
                hasContinueListening: model.continueListeningBookID(in: books) != nil
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            LibraryDetailLayout {
                LibraryGridView(
                    books: displayedBooks,
                    selection: $model.selectedBookID,
                    canPlay: model.canPlay,
                    play: play,
                    openZen: openZen,
                    bottomContentInset: playerContext == nil ? 0 : 118,
                    artworkURL: artworkURL
                )
            } player: {
                if let playerContext,
                    let playback = environment.playbackCoordinator
                {
                    FloatingPlaybackBar(
                        book: playerContext.book,
                        presentation: playerContext.presentation,
                        artworkURL: artworkURL(for: playerContext.book),
                        currentWordOffset: playback.currentNormalizedWordOffset,
                        totalWordCount: playerContext.book.indexedWordCount,
                        narrationRate: playerContext.book.narrationRate,
                        previousChapter: { Task { await playback.previousChapter() } },
                        skipBackward: { Task { await playback.seek(by: -15) } },
                        togglePlayback: { togglePlayback(for: playerContext.book) },
                        skipForward: { Task { await playback.seek(by: 15) } },
                        nextChapter: { Task { await playback.nextChapter() } },
                        seek: { target in Task { await playback.seek(toNormalizedWordOffset: target) } },
                        openZen: { openZen(playerContext.book) }
                    )
                    .frame(maxWidth: 980)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .transition(playerTransition)
                }
            }
            .navigationTitle(title)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search books")
        .toolbar {
            LibraryToolbar(
                playbackSymbol: playbackSymbol,
                canPlay: model.canPlay(selectedBook),
                canOpenZen: model.canPlay(selectedBook),
                importBooks: { model.isImporting = true },
                togglePlayback: togglePlayback,
                openZen: {
                    if let selectedBook { openZen(selectedBook) }
                }
            )
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: playerContext?.book.id
        )
        .focusedSceneValue(\.libraryCommandActions, commandActions)
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: BookImportContentTypes.all,
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await environment.importBooks(from: urls) }
        }
        .alert("Import Failed", isPresented: importErrorIsPresented) {
            Button("OK") { environment.lastActionError = nil }
        } message: {
            Text(environment.lastActionError ?? "The book could not be imported.")
        }
        .onChange(of: model.selectedBookID) { _, newValue in
            environment.selectedBookID = newValue
        }
        .onAppear {
            if model.selectedBookID == nil { model.selectedBookID = environment.selectedBookID }
        }
        .task {
            await environment.rescanLibrary()
        }
    }

    private var title: String {
        switch model.collection {
        case .allBooks: "All Books"
        case .continueListening: "Continue Listening"
        case .preparing: "Preparing"
        }
    }

    private var playbackSymbol: String {
        guard environment.playbackCoordinator?.currentBookID == selectedBook?.id,
            environment.playbackCoordinator?.state == .playing
        else { return "play.fill" }
        return "pause.fill"
    }

    private var activePlaybackContext: LibraryPlaybackBarContext? {
        guard let playback = environment.playbackCoordinator else { return nil }
        return LibraryPlaybackBarContext.make(
            books: books,
            currentBookID: playback.currentBookID,
            state: playback.state,
            chapterTitle: playback.currentChapterTitle
        )
    }

    private var playerTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    private var commandActions: LibraryCommandActions {
        LibraryCommandActions(
            importBooks: { model.isImporting = true },
            togglePlayback: togglePlayback,
            openZen: {
                if let selectedBook { openZen(selectedBook) }
            },
            canPlay: model.canPlay(selectedBook),
            canOpenZen: model.canPlay(selectedBook)
        )
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(
            get: { environment.lastActionError != nil },
            set: { if !$0 { environment.lastActionError = nil } }
        )
    }

    private func play(_ book: LibraryBookRecord) {
        model.selectedBookID = book.id
        Task { await environment.playbackCoordinator?.play(bookID: book.id) }
    }

    private func togglePlayback() {
        guard let selectedBook, model.canPlay(selectedBook) else { return }
        togglePlayback(for: selectedBook)
    }

    private func togglePlayback(for book: LibraryBookRecord) {
        guard let playback = environment.playbackCoordinator else { return }
        if playback.currentBookID != book.id {
            Task { await playback.play(bookID: book.id) }
        } else if playback.state == .playing {
            playback.pause()
        } else if playback.state == .paused {
            playback.resume()
        } else if playback.state == .stopped {
            Task { await playback.play(bookID: book.id) }
        }
    }

    private func artworkURL(for book: LibraryBookRecord) -> URL? {
        environment.libraryStore?.artworkURL(for: book)
    }

    private func openZen(_ book: LibraryBookRecord) {
        model.selectedBookID = book.id
        openWindow(value: book.id)
    }
}

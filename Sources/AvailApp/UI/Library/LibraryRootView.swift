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
                preparingCount: books.filter { $0.state == .copying || $0.state == .indexing }.count,
                hasContinueListening: model.continueListeningBookID(in: books) != nil
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            LibraryGridView(
                books: displayedBooks,
                selection: $model.selectedBookID,
                canPlay: model.canPlay,
                play: play,
                openZen: openZen
            )
            .navigationTitle(title)
            .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search books")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Import", systemImage: "plus") { model.isImporting = true }
                        .help("Import EPUB or PDF books")
                    Button("Listen", systemImage: playbackSymbol) { togglePlayback() }
                        .disabled(!model.canPlay(selectedBook))
                        .help("Play or pause the selected book")
                    Button("Open Zen", systemImage: "rectangle.split.2x1") {
                        if let selectedBook { openZen(selectedBook) }
                    }
                    .disabled(!model.canPlay(selectedBook))
                    .help("Open the focused listening and reading window")
                }
            }
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
        environment.playbackCoordinator?.state == .playing ? "pause.fill" : "play.fill"
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
        guard let selectedBook, model.canPlay(selectedBook), let playback = environment.playbackCoordinator else { return }
        if playback.state == .playing {
            playback.pause()
        } else if playback.currentBookID == selectedBook.id, playback.state == .paused {
            playback.resume()
        } else {
            Task { await playback.play(bookID: selectedBook.id) }
        }
    }

    private func openZen(_ book: LibraryBookRecord) {
        model.selectedBookID = book.id
        openWindow(value: book.id)
    }
}

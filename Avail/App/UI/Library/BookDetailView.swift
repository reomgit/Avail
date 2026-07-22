import AppKit
import AvailCore
import SwiftUI

struct BookDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    let bookID: UUID

    @State private var model = BookDetailViewModel()
    @State private var pendingRemoval: LibraryRemovalMode?

    var body: some View {
        Group {
            if let book = model.book {
                bookContent(book)
            } else if model.isLoading {
                ProgressView("Loading Book…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Book Unavailable",
                    systemImage: "book.closed",
                    description: Text(model.errorMessage ?? "This library record no longer exists.")
                )
            }
        }
        .navigationTitle(model.book?.title ?? "Book")
        .navigationSubtitle(model.book?.author ?? "")
        .task {
            await model.load(
                bookID: bookID,
                libraryStore: environment.libraryStore,
                indexStore: environment.indexStore
            )
        }
        .task(id: indexingProgress?.indexedWordCount) {
            await model.refreshSections(bookID: bookID, indexStore: environment.indexStore)
        }
        .confirmationDialog(
            removalTitle,
            isPresented: removalIsPresented,
            titleVisibility: .visible
        ) {
            Button(removalButtonTitle, role: .destructive) {
                removeBook()
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(removalMessage)
        }
    }

    private func bookContent(_ book: LibraryBookRecord) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                hero(book)

                if book.state == .missing {
                    RecoveryView(issue: .missingSource) { action in
                        if action == .removeFromLibrary { pendingRemoval = .recordOnly }
                    }
                    .frame(minHeight: 250)
                } else if book.state == .failed {
                    RecoveryView(issue: .indexInterrupted) { action in
                        if action == .retryIndex {
                            environment.indexingCoordinator?.retry(bookID: book.id)
                        }
                    }
                    .frame(minHeight: 250)
                }

                preparationProgress(book)
                chapters(book)
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
    }

    private func hero(_ book: LibraryBookRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 34) {
                heroArtwork(book, width: 220)
                heroMetadata(book)
                    .padding(.top, 8)
            }
            .frame(minWidth: 700, alignment: .leading)

            VStack(alignment: .leading, spacing: 24) {
                heroArtwork(book, width: 180)
                heroMetadata(book)
            }
        }
        .background(alignment: .leading) {
            BookArtworkView(
                book: book,
                artworkURL: artworkURL(for: book),
                cornerRadius: 24
            )
            .frame(width: 260)
            .blur(radius: 46)
            .opacity(0.14)
            .scaleEffect(1.22)
            .backgroundExtensionEffect()
            .accessibilityHidden(true)
        }
    }

    private func heroArtwork(_ book: LibraryBookRecord, width: CGFloat) -> some View {
        BookArtworkView(
            book: book,
            artworkURL: artworkURL(for: book),
            cornerRadius: 12
        )
        .frame(width: width)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
    }

    private func heroMetadata(_ book: LibraryBookRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .textSelection(.enabled)
                Text(book.author ?? "Unknown Author")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Label(
                    "\(book.format.rawValue.uppercased()) · \(BookStatePresentation(state: book.state).label)",
                    systemImage: BookStatePresentation(state: book.state).systemImage
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if book.indexedWordCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: listeningProgress(book))
                    Text(listeningProgressText(book))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button(primaryActionTitle(book), systemImage: primaryActionSymbol(book)) {
                    togglePlayback(book)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(!canPlay(book))

                Button("Open Zen", systemImage: "rectangle.split.2x1") {
                    openWindow(value: book.id)
                }
                .buttonStyle(.glass)
                .disabled(!canPlay(book))

                moreMenu(book)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func preparationProgress(_ book: LibraryBookRecord) -> some View {
        if !book.isIndexComplete && book.state != .missing && book.state != .failed {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preparing")
                    .font(.title2.bold())

                if let progress = indexingProgress,
                    let total = progress.totalSourceUnits,
                    total > 0
                {
                    ProgressView(
                        value: Double(progress.completedSourceUnits),
                        total: Double(total)
                    )
                } else {
                    ProgressView()
                }

                Text(preparationText(book))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func chapters(_ book: LibraryBookRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters")
                .font(.title2.bold())

            if model.sections.isEmpty {
                ContentUnavailableView(
                    book.isIndexComplete ? "No Chapters" : "Chapters Are Preparing",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        book.isIndexComplete
                            ? "This book does not contain any speakable sections."
                            : "Committed chapters will appear here as they become available."
                    )
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                        Button {
                            Task {
                                await environment.playbackCoordinator?.play(
                                    bookID: book.id,
                                    startingAt: section.id
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(section.title ?? "Chapter \(index + 1)")
                                        .font(.body.weight(.medium))
                                    Text("Chapter \(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                            .padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
                        .disabled(section.chunkIDs.isEmpty)
                        .accessibilityHint("Start listening from this chapter")

                        if index < model.sections.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func moreMenu(_ book: LibraryBookRecord) -> some View {
        Menu {
            if book.state == .failed {
                Button("Retry Preparing", systemImage: "arrow.clockwise") {
                    environment.indexingCoordinator?.retry(bookID: book.id)
                }
            }
            Button("Reveal in Finder", systemImage: "folder") {
                revealInFinder(book)
            }
            .disabled(book.state == .missing)

            Divider()

            Button("Remove from Library", systemImage: "minus.circle") {
                pendingRemoval = .recordOnly
            }
            Button("Move File to Trash", systemImage: "trash", role: .destructive) {
                pendingRemoval = .moveFileToTrash
            }
            .disabled(book.state == .missing)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .help("More actions for \(book.title)")
    }

    private var indexingProgress: IndexingProgress? {
        environment.indexingCoordinator?.progress(for: bookID)
    }

    private func canPlay(_ book: LibraryBookRecord) -> Bool {
        book.state != .missing && book.state != .failed && book.isPlayable
    }

    private func primaryActionTitle(_ book: LibraryBookRecord) -> String {
        guard let playback = environment.playbackCoordinator,
            playback.currentBookID == book.id
        else {
            return book.positionUpdatedAt == nil ? "Listen" : "Continue"
        }
        return playback.state == .playing ? "Pause" : "Continue"
    }

    private func primaryActionSymbol(_ book: LibraryBookRecord) -> String {
        guard environment.playbackCoordinator?.currentBookID == book.id,
            environment.playbackCoordinator?.state == .playing
        else { return "play.fill" }
        return "pause.fill"
    }

    private func togglePlayback(_ book: LibraryBookRecord) {
        guard let playback = environment.playbackCoordinator else { return }
        if playback.currentBookID != book.id {
            Task { await playback.play(bookID: book.id) }
        } else if playback.state == .playing {
            playback.pause()
        } else if playback.state == .paused {
            playback.resume()
        } else {
            Task { await playback.play(bookID: book.id) }
        }
    }

    private func listeningProgress(_ book: LibraryBookRecord) -> Double {
        guard book.indexedWordCount > 0 else { return 0 }
        let offset: Int
        if environment.playbackCoordinator?.currentBookID == book.id {
            offset = environment.playbackCoordinator?.currentNormalizedWordOffset ?? 0
        } else {
            offset = book.normalizedWordOffset
        }
        return min(1, max(0, Double(offset) / Double(book.indexedWordCount)))
    }

    private func listeningProgressText(_ book: LibraryBookRecord) -> String {
        let percentage = (listeningProgress(book) * 100)
            .formatted(.number.precision(.fractionLength(0)))
        return book.positionUpdatedAt == nil ? "Not started" : "\(percentage) percent complete"
    }

    private func preparationText(_ book: LibraryBookRecord) -> String {
        let words = max(book.indexedWordCount, indexingProgress?.indexedWordCount ?? 0)
        if book.isPlayable {
            return "\(words.formatted()) words are ready. You can listen while preparation continues."
        }
        return "\(words.formatted()) words prepared. Listening becomes available after the first passage is ready."
    }

    private func artworkURL(for book: LibraryBookRecord) -> URL? {
        environment.libraryStore?.artworkURL(for: book)
    }

    private func revealInFinder(_ book: LibraryBookRecord) {
        do {
            let access = try environment.libraryStore?.accessBookFile(bookID: book.id)
            if let url = access?.url {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            environment.lastActionError = "The book file could not be revealed in Finder."
        }
    }

    private var removalIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private var removalTitle: String {
        pendingRemoval == .moveFileToTrash
            ? "Move this book to the Trash?"
            : "Remove this book from Avail?"
    }

    private var removalButtonTitle: String {
        pendingRemoval == .moveFileToTrash ? "Move to Trash" : "Remove from Library"
    }

    private var removalMessage: String {
        pendingRemoval == .moveFileToTrash
            ? "The managed EPUB or PDF will be moved to the Trash, where it can still be recovered."
            : "The library record and artwork will be removed. The EPUB or PDF stays in your library folder."
    }

    private func removeBook() {
        guard let mode = pendingRemoval else { return }
        pendingRemoval = nil
        Task {
            do {
                try await environment.removeBook(bookID: bookID, mode: mode)
                dismiss()
            } catch {
                environment.lastActionError = "Avail could not remove this book."
            }
        }
    }
}

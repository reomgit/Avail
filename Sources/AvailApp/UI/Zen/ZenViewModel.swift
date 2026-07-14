import AvailCore
import AvailPlayback
import Foundation
import Observation
import SwiftUI

struct ZenScrollRequest: Equatable {
    let id: UUID
    let chunkID: UUID
    let animated: Bool
}

struct ZenCommandActions {
    var togglePlayback: () -> Void
    var seekBackward: () -> Void
    var seekForward: () -> Void
    var previousChapter: () -> Void
    var nextChapter: () -> Void
}

private struct ZenCommandActionsKey: FocusedValueKey {
    typealias Value = ZenCommandActions
}

extension FocusedValues {
    var zenCommandActions: ZenCommandActions? {
        get { self[ZenCommandActionsKey.self] }
        set { self[ZenCommandActionsKey.self] = newValue }
    }
}

@MainActor
@Observable
final class ZenViewModel {
    let bookID: UUID
    let playback: PlaybackCoordinator
    private let libraryStore: LibraryStore
    private let indexStore: ReadingIndexStore

    private(set) var book: LibraryBookRecord?
    private(set) var chunks: [SpeechChunk] = []
    private(set) var sections: [ReadingSection] = []
    private(set) var isFollowingNarration = true
    private(set) var scrollRequest: ZenScrollRequest?
    private(set) var loadError: String?

    var showsReturnToNarration: Bool { !isFollowingNarration }
    var isConnectedToActivePlayback: Bool { playback.currentBookID == bookID }
    var currentSectionID: UUID? { playback.currentChunk?.sectionID }
    var currentChapterTitle: String? {
        sections.first(where: { $0.id == currentSectionID })?.title
    }
    var availableVoices: [NarrationVoice] {
        guard let languageCode = book?.languageCode, !languageCode.isEmpty else {
            return playback.availableVoices
        }
        let matching = playback.availableVoices.filter { $0.matches(languageCode: languageCode) }
        return matching.isEmpty ? playback.availableVoices : matching
    }

    init(
        bookID: UUID,
        libraryStore: LibraryStore,
        indexStore: ReadingIndexStore,
        playback: PlaybackCoordinator
    ) {
        self.bookID = bookID
        self.libraryStore = libraryStore
        self.indexStore = indexStore
        self.playback = playback
    }

    func load() async {
        do {
            book = try libraryStore.book(id: bookID)
            chunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
            sections = try await indexStore.sections(bookID: bookID).sorted { $0.ordinal < $1.ordinal }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func highlightedStringRange(in chunk: SpeechChunk) -> Range<String.Index>? {
        guard playback.highlightedChunkID == chunk.id,
              let range = playback.highlightRange,
              range.location >= 0,
              range.length >= 0,
              range.location + range.length <= chunk.text.utf16.count else { return nil }
        return Range(range, in: chunk.text)
    }

    func highlightedSubstring(in chunk: SpeechChunk) -> String? {
        guard let range = highlightedStringRange(in: chunk) else { return nil }
        return String(chunk.text[range])
    }

    func userDidScroll() {
        isFollowingNarration = false
    }

    func returnToNarration(reduceMotion: Bool) {
        isFollowingNarration = true
        guard let chunkID = playback.highlightedChunkID ?? playback.currentChunk?.id ?? chunks.first?.id else { return }
        scrollRequest = ZenScrollRequest(id: UUID(), chunkID: chunkID, animated: !reduceMotion)
    }

    func requestFollowScroll(reduceMotion: Bool) {
        guard isFollowingNarration,
              let chunkID = playback.highlightedChunkID ?? playback.currentChunk?.id else { return }
        scrollRequest = ZenScrollRequest(id: UUID(), chunkID: chunkID, animated: !reduceMotion)
    }

    func togglePlayback() {
        if playback.state == .playing {
            playback.pause()
        } else if playback.currentBookID == bookID, playback.state == .paused {
            playback.resume()
        } else {
            Task { await playback.play(bookID: bookID) }
        }
    }

    func setRate(_ rate: Double) {
        playback.setNarrationRate(rate, bookID: bookID)
    }

    func setVoiceIdentifier(_ voiceIdentifier: String?) {
        playback.setVoiceIdentifier(voiceIdentifier, bookID: bookID)
    }

    func seek(to wordOffset: Int) {
        Task { await playback.seek(toNormalizedWordOffset: wordOffset) }
    }

    func selectChapter(_ sectionID: UUID) {
        Task { await playback.goToChapter(sectionID: sectionID) }
    }

    func windowWillClose() {
        // Playback is application-wide by design; closing Zen only releases its view state.
    }

    var commandActions: ZenCommandActions {
        ZenCommandActions(
            togglePlayback: togglePlayback,
            seekBackward: { [weak self] in Task { await self?.playback.seek(by: -15) } },
            seekForward: { [weak self] in Task { await self?.playback.seek(by: 15) } },
            previousChapter: { [weak self] in Task { await self?.playback.previousChapter() } },
            nextChapter: { [weak self] in Task { await self?.playback.nextChapter() } }
        )
    }
}

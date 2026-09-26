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

enum ZenPlaybackToggleAction: Equatable {
    case start
    case pause
    case resume
    case unavailable
}

struct ZenPlaybackControlState: Equatable {
    let isPlaying: Bool
    let canTogglePlayback: Bool
    let toggleAction: ZenPlaybackToggleAction

    static func make(
        bookID: UUID,
        currentBookID: UUID?,
        playbackState: PlaybackState
    ) -> ZenPlaybackControlState {
        guard currentBookID == bookID else {
            return ZenPlaybackControlState(
                isPlaying: false,
                canTogglePlayback: true,
                toggleAction: .start
            )
        }

        switch playbackState {
        case .stopped:
            return ZenPlaybackControlState(isPlaying: false, canTogglePlayback: true, toggleAction: .start)
        case .playing:
            return ZenPlaybackControlState(isPlaying: true, canTogglePlayback: true, toggleAction: .pause)
        case .paused:
            return ZenPlaybackControlState(isPlaying: false, canTogglePlayback: true, toggleAction: .resume)
        case .preparingVoice:
            return ZenPlaybackControlState(isPlaying: false, canTogglePlayback: true, toggleAction: .pause)
        case .bufferingForIndex, .seeking, .failed:
            return ZenPlaybackControlState(
                isPlaying: false,
                canTogglePlayback: false,
                toggleAction: .unavailable
            )
        }
    }
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
    var playbackControlState: ZenPlaybackControlState {
        ZenPlaybackControlState.make(
            bookID: bookID,
            currentBookID: playback.currentBookID,
            playbackState: playback.state
        )
    }
    var playbackPresentation: PlaybackBarPresentation? {
        PlaybackBarPresentation.make(
            book: book,
            state: isConnectedToActivePlayback ? playback.state : .stopped,
            chapterTitle: currentChapterTitle
        )
    }
    var currentSectionID: UUID? { playback.currentChunk?.sectionID }
    var currentChapterTitle: String? {
        if isConnectedToActivePlayback, let currentChapterTitle = playback.currentChapterTitle {
            return currentChapterTitle
        }
        return sections.first(where: { $0.id == currentSectionID })?.title
    }
    var artworkURL: URL? {
        guard let book else { return nil }
        return libraryStore.artworkURL(for: book)
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
            range.location + range.length <= chunk.text.utf16.count
        else { return nil }
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
            let chunkID = playback.highlightedChunkID ?? playback.currentChunk?.id
        else { return }
        scrollRequest = ZenScrollRequest(id: UUID(), chunkID: chunkID, animated: !reduceMotion)
    }

    func togglePlayback() {
        switch playbackControlState.toggleAction {
        case .start:
            Task { await playback.play(bookID: bookID) }
        case .pause:
            playback.pause()
        case .resume:
            playback.resume()
        case .unavailable:
            break
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
        Task { await playback.play(bookID: bookID, startingAt: sectionID) }
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

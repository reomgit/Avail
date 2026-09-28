import AvailCore
import AvailPlayback
import Foundation
import NaturalLanguage
import Observation

enum PlaybackState: Equatable {
    case stopped
    case bufferingForIndex
    case preparingVoice
    case playing
    case paused
    case seeking
    case failed(String)
}

@MainActor
@Observable
final class PlaybackCoordinator {
    private let engine: any NarrationEngine
    private let indexStore: ReadingIndexStore
    private let libraryStore: LibraryStore
    private let indexingCoordinator: any IndexingPrioritizing
    private let nowPlaying: any NowPlayingControlling
    private let persistence: PlaybackPersistence
    private var narrationEventTask: Task<Void, Never>?
    private var indexingUpdateTask: Task<Void, Never>?
    private var queuedChunks: [SpeechChunk] = []
    private var currentChunkGlobalWordOffset = 0
    private var currentUTF16Offset = 0
    private var currentAudioResume: AudioResumePoint?
    private var activeVoiceIdentifier: String?
    private(set) var currentNormalizedWordOffset = 0
    private var currentArtworkData: Data?

    private(set) var state: PlaybackState = .stopped
    private(set) var currentBookID: UUID?
    private(set) var currentChunk: SpeechChunk?
    private(set) var currentChapterTitle: String?
    private(set) var currentChapterNumber: Int?
    private(set) var highlightedChunkID: UUID?
    private(set) var highlightRange: NSRange?
    var followMode = true

    var availableVoices: [NarrationVoice] { engine.voices }

    init(
        engine: any NarrationEngine,
        indexStore: ReadingIndexStore,
        libraryStore: LibraryStore,
        indexingCoordinator: any IndexingPrioritizing,
        nowPlaying: any NowPlayingControlling = NowPlayingController(),
        persistenceDebounce: Duration = .seconds(1)
    ) {
        self.engine = engine
        self.indexStore = indexStore
        self.libraryStore = libraryStore
        self.indexingCoordinator = indexingCoordinator
        self.nowPlaying = nowPlaying
        self.persistence = PlaybackPersistence(libraryStore: libraryStore, debounce: persistenceDebounce)
        observeNarrationEvents()
        observeIndexingUpdates()
        installRemoteCommands()
    }

    func play(bookID: UUID, startingAt sectionID: UUID? = nil) async {
        if currentBookID == bookID {
            if let sectionID {
                await goToChapter(sectionID: sectionID)
                return
            }
            switch state {
            case .paused:
                resume()
                return
            case .failed:
                speakCurrentChunk()
                return
            case .stopped:
                if currentChunk != nil {
                    speakCurrentChunk()
                    return
                }
            default:
                return
            }
        }

        if currentBookID != nil {
            persistImmediately()
            engine.stop()
        }

        do {
            guard let record = try libraryStore.book(id: bookID) else { throw LibraryError.missingRecord }
            currentArtworkData = libraryStore.artworkData(for: record)
            currentBookID = bookID
            currentChapterTitle = nil
            currentChapterNumber = nil
            highlightedChunkID = nil
            highlightRange = nil
            try await restore(record: record, startingAt: sectionID)
            if currentChunk == nil {
                await bufferForIndex(after: nil)
                return
            }
            speakCurrentChunk()
            await updateNowPlaying()
        } catch {
            setState(.failed(String(describing: error)))
        }
    }

    func pause() {
        guard currentChunk != nil, state != .preparingVoice else { return }
        engine.pause()
        setState(.paused)
        persistImmediately()
    }

    func resume() {
        guard currentChunk != nil, state != .preparingVoice else { return }
        if let currentBookID,
            let selectedVoiceIdentifier = try? libraryStore.book(id: currentBookID)?.voiceIdentifier,
            selectedVoiceIdentifier != activeVoiceIdentifier
        {
            engine.stop()
            speakCurrentChunk()
            return
        }
        engine.resume()
        setState(.playing)
    }

    func stop() {
        persistImmediately()
        engine.stop()
        setState(.stopped)
    }

    func clearSession(for bookID: UUID) {
        guard currentBookID == bookID else { return }
        persistImmediately()
        engine.stop()
        queuedChunks = []
        currentBookID = nil
        currentChunk = nil
        currentChapterTitle = nil
        currentChapterNumber = nil
        highlightedChunkID = nil
        highlightRange = nil
        currentChunkGlobalWordOffset = 0
        currentUTF16Offset = 0
        currentNormalizedWordOffset = 0
        currentArtworkData = nil
        followMode = true
        setState(.stopped)
    }

    func seek(by seconds: TimeInterval) async {
        guard let bookID = currentBookID,
            let record = try? libraryStore.book(id: bookID)
        else { return }
        let wordsPerSecond = 2.5 * max(0.5, min(record.narrationRate, 2))
        let target = max(0, currentNormalizedWordOffset + Int(seconds * wordsPerSecond))
        await seek(toNormalizedWordOffset: target)
    }

    func seek(toNormalizedWordOffset target: Int) async {
        guard let bookID = currentBookID else { return }
        setState(.seeking)
        do {
            guard let position = try await indexStore.position(bookID: bookID, normalizedWordOffset: target) else {
                let manifest = try await indexStore.manifest(bookID: bookID)
                if manifest.isComplete { setState(.stopped) } else { await bufferForIndex(after: currentChunk?.locator) }
                return
            }
            try await move(to: position.chunk, requestedWordOffset: position.globalWordOffset, stopFirst: true)
        } catch {
            setState(.failed(String(describing: error)))
        }
    }

    func goToChapter(sectionID: UUID) async {
        guard let bookID = currentBookID else { return }
        do {
            let sections = try await indexStore.sections(bookID: bookID)
            let chunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
            guard let section = sections.first(where: { $0.id == sectionID }),
                let chunk = section.chunkIDs.compactMap({ id in chunks.first(where: { $0.id == id }) }).first
            else {
                return
            }
            try await move(to: chunk, requestedWordOffset: nil, stopFirst: true)
        } catch {
            setState(.failed(String(describing: error)))
        }
    }

    func setNarrationRate(_ rate: Double, bookID: UUID) {
        try? libraryStore.saveNarrationRate(rate, bookID: bookID)
        restartCurrentUtteranceIfNeeded(bookID: bookID)
    }

    func setVoiceIdentifier(_ voiceIdentifier: String?, bookID: UUID) {
        try? libraryStore.saveVoiceIdentifier(voiceIdentifier, bookID: bookID)
        restartCurrentUtteranceIfNeeded(bookID: bookID)
    }

    func nextChapter() async {
        await moveChapter(direction: 1)
    }

    func previousChapter() async {
        await moveChapter(direction: -1)
    }

    func applicationWillTerminate() {
        persistImmediately()
        nowPlaying.teardown()
    }

    private func restore(record: LibraryBookRecord, startingAt sectionID: UUID? = nil) async throws {
        let allChunks = try await indexStore.chunks(bookID: record.id, around: nil, limit: .max)
        guard !allChunks.isEmpty else {
            currentChunk = nil
            queuedChunks = []
            return
        }

        if let sectionID,
            let sectionStartIndex = allChunks.firstIndex(where: { $0.sectionID == sectionID })
        {
            let globalStart = allChunks[..<sectionStartIndex].reduce(0) { $0 + $1.wordCount }
            configureCurrent(
                chunks: Array(allChunks[sectionStartIndex..<min(sectionStartIndex + 2, allChunks.count)]),
                globalStart: globalStart,
                utf16Offset: 0,
                normalizedWordOffset: globalStart,
                audioResume: nil
            )
            return
        }

        if let saved = record.readingPosition(),
            let exactIndex = allChunks.firstIndex(where: { $0.id == saved.chunkID })
        {
            let globalStart = allChunks[..<exactIndex].reduce(0) { $0 + $1.wordCount }
            configureCurrent(
                chunks: Array(allChunks[exactIndex..<min(exactIndex + 2, allChunks.count)]),
                globalStart: globalStart,
                utf16Offset: saved.utf16Offset,
                normalizedWordOffset: saved.normalizedWordOffset,
                audioResume: saved.audioResume
            )
            return
        }

        let requestedOffset = record.readingPosition()?.normalizedWordOffset ?? 0
        guard let fallback = try await indexStore.position(bookID: record.id, normalizedWordOffset: requestedOffset),
            let fallbackIndex = allChunks.firstIndex(where: { $0.id == fallback.chunk.id })
        else {
            currentChunk = nil
            queuedChunks = []
            return
        }
        configureCurrent(
            chunks: Array(allChunks[fallbackIndex..<min(fallbackIndex + 2, allChunks.count)]),
            globalStart: fallback.globalWordOffset,
            utf16Offset: 0,
            normalizedWordOffset: fallback.globalWordOffset,
            audioResume: nil
        )
    }

    private func configureCurrent(
        chunks: [SpeechChunk],
        globalStart: Int,
        utf16Offset: Int,
        normalizedWordOffset: Int,
        audioResume: AudioResumePoint? = nil
    ) {
        queuedChunks = Array(chunks.prefix(2))
        currentChunk = queuedChunks.first
        currentChunkGlobalWordOffset = globalStart
        currentUTF16Offset = utf16Offset
        currentNormalizedWordOffset = normalizedWordOffset
        currentAudioResume = audioResume
    }

    private func speakCurrentChunk() {
        guard let currentChunk,
            let bookID = currentBookID,
            let record = try? libraryStore.book(id: bookID)
        else { return }
        let rate = Float(0.5 * max(0.5, min(record.narrationRate, 2)))
        let speedMultiplier = Float(max(0.5, min(record.narrationRate, 2)))
        activeVoiceIdentifier = record.voiceIdentifier
        engine.speak(
            NarrationRequest(
                chunk: currentChunk,
                voiceIdentifier: record.voiceIdentifier,
                languageCode: record.languageCode,
                rate: rate,
                speedMultiplier: speedMultiplier,
                startUTF16Offset: currentUTF16Offset,
                audioResume: currentAudioResume
            )
        )
        setState(record.voiceIdentifier?.hasPrefix("neural:") == true ? .preparingVoice : .playing)
    }

    private func advanceAfterFinishedChunk() async {
        guard let bookID = currentBookID, let currentChunk else { return }
        do {
            let allChunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
            if let currentIndex = allChunks.firstIndex(where: { $0.id == currentChunk.id }),
                allChunks.indices.contains(currentIndex + 1)
            {
                let next = allChunks[currentIndex + 1]
                try await move(to: next, requestedWordOffset: currentChunkGlobalWordOffset + currentChunk.wordCount, stopFirst: false)
                return
            }
            let manifest = try await indexStore.manifest(bookID: bookID)
            if manifest.isComplete {
                persistImmediately()
                setState(.stopped)
            } else {
                await bufferForIndex(after: currentChunk.locator)
            }
        } catch {
            setState(.failed(String(describing: error)))
        }
    }

    private func move(to chunk: SpeechChunk, requestedWordOffset: Int?, stopFirst: Bool) async throws {
        guard let bookID = currentBookID else { return }
        let allChunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
        guard let index = allChunks.firstIndex(where: { $0.id == chunk.id }) else { return }
        if stopFirst { engine.stop() }
        let globalStart = allChunks[..<index].reduce(0) { $0 + $1.wordCount }
        configureCurrent(
            chunks: Array(allChunks[index..<min(index + 2, allChunks.count)]),
            globalStart: globalStart,
            utf16Offset: 0,
            normalizedWordOffset: requestedWordOffset ?? globalStart,
            audioResume: nil
        )
        persistImmediately()
        speakCurrentChunk()
        await updateNowPlaying()
    }

    private func moveChapter(direction: Int) async {
        guard let bookID = currentBookID, let currentChunk else { return }
        do {
            let sections = try await indexStore.sections(bookID: bookID).sorted { $0.ordinal < $1.ordinal }
            let chunks = try await indexStore.chunks(bookID: bookID, around: nil, limit: .max)
            guard let currentSectionIndex = sections.firstIndex(where: { $0.id == currentChunk.sectionID }) else { return }
            var index = currentSectionIndex + direction
            while sections.indices.contains(index) {
                if let target = sections[index].chunkIDs.compactMap({ id in chunks.first(where: { $0.id == id }) }).first {
                    try await move(to: target, requestedWordOffset: nil, stopFirst: true)
                    return
                }
                index += direction
            }
        } catch {
            setState(.failed(String(describing: error)))
        }
    }

    private func bufferForIndex(after locator: SourceLocator?) async {
        guard let bookID = currentBookID else { return }
        engine.stop()
        setState(.bufferingForIndex)
        indexingCoordinator.prioritize(bookID: bookID, after: locator)
    }

    private func resumeAfterIndexUpdate(_ update: IndexingUpdate) async {
        guard state == .bufferingForIndex,
            update.bookID == currentBookID,
            update.progress.phase != .failed
        else { return }
        await advanceAfterFinishedChunk()
    }

    private func handle(_ event: NarrationEvent) async {
        switch event {
        case let .voiceFallback(_, selectedIdentifier):
            if let currentBookID { try? libraryStore.saveVoiceIdentifier(selectedIdentifier, bookID: currentBookID) }
        case .started:
            setState(.playing)
            await updateNowPlaying()
        case .preparing:
            setState(.preparingVoice)
        case let .willSpeakRange(chunkID, range):
            guard chunkID == currentChunk?.id, let currentChunk else { return }
            highlightedChunkID = chunkID
            highlightRange = range
            currentUTF16Offset = range.location
            currentAudioResume = nil
            currentNormalizedWordOffset =
                currentChunkGlobalWordOffset
                + wordCount(
                    beforeUTF16Offset: range.location,
                    in: currentChunk.text
                )
            if let position = currentPosition() { persistence.schedule(position) }
            await updateNowPlaying()
        case let .audioPosition(chunkID, range, resume):
            guard chunkID == currentChunk?.id else { return }
            highlightedChunkID = chunkID
            highlightRange = range
            currentUTF16Offset = range.location
            currentAudioResume = resume
            if let currentChunk {
                currentNormalizedWordOffset =
                    currentChunkGlobalWordOffset
                    + wordCount(
                        beforeUTF16Offset: range.location,
                        in: currentChunk.text
                    )
            }
            if let position = currentPosition() { persistence.schedule(position) }
        case let .phraseFinished(chunkID, nextUTF16Offset):
            guard chunkID == currentChunk?.id else { return }
            currentUTF16Offset = nextUTF16Offset
            currentAudioResume = nil
            if let currentChunk {
                currentNormalizedWordOffset =
                    currentChunkGlobalWordOffset
                    + wordCount(
                        beforeUTF16Offset: nextUTF16Offset,
                        in: currentChunk.text
                    )
            }
            persistImmediately()
            speakCurrentChunk()
        case let .failed(chunkID, reason):
            guard chunkID == currentChunk?.id else { return }
            persistImmediately()
            setState(.failed(reason))
        case .paused:
            setState(.paused)
            persistImmediately()
        case .resumed:
            setState(.playing)
            await updateNowPlaying()
        case let .finished(chunkID):
            if chunkID == currentChunk?.id { await advanceAfterFinishedChunk() }
        case let .cancelled(chunkID):
            if chunkID == currentChunk?.id { persistImmediately() }
        }
    }

    private func wordCount(beforeUTF16Offset offset: Int, in text: String) -> Int {
        let length = min(max(0, offset), text.utf16.count)
        let prefix = (text as NSString).substring(with: NSRange(location: 0, length: length))
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = prefix
        var count = 0
        tokenizer.enumerateTokens(in: prefix.startIndex..<prefix.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    private func currentPosition() -> ReadingPosition? {
        guard let bookID = currentBookID, let currentChunk else { return nil }
        return ReadingPosition(
            bookID: bookID,
            sectionID: currentChunk.sectionID,
            chunkID: currentChunk.id,
            utf16Offset: currentUTF16Offset,
            normalizedWordOffset: currentNormalizedWordOffset,
            updatedAt: Date(),
            audioResume: currentAudioResume
        )
    }

    private func persistImmediately() {
        persistence.flush(currentPosition())
    }

    private func restartCurrentUtteranceIfNeeded(bookID: UUID) {
        guard currentBookID == bookID, currentChunk != nil else { return }
        switch state {
        case .playing:
            if activeVoiceIdentifier?.hasPrefix("neural:") == true { return }
        case .failed:
            break
        default:
            return
        }
        engine.stop()
        speakCurrentChunk()
    }

    private func setState(_ newState: PlaybackState) {
        state = newState
        nowPlaying.updatePlaybackState(newState)
    }

    private func updateNowPlaying() async {
        guard let bookID = currentBookID,
            let record = try? libraryStore.book(id: bookID),
            let currentChunk
        else { return }
        let sections = (try? await indexStore.sections(bookID: bookID).sorted { $0.ordinal < $1.ordinal }) ?? []
        let sectionIndex = sections.firstIndex(where: { $0.id == currentChunk.sectionID })
        currentChapterTitle = sectionIndex.flatMap { sections[$0].title }
        currentChapterNumber = sectionIndex.map { $0 + 1 }
        let wordsPerSecond = 2.5 * max(0.5, min(record.narrationRate, 2))
        nowPlaying.update(
            NowPlayingSnapshot(
                title: record.title,
                artist: record.author,
                chapterTitle: currentChapterTitle,
                chapterNumber: currentChapterNumber,
                artworkData: currentArtworkData,
                estimatedDuration: Double(record.indexedWordCount) / wordsPerSecond,
                elapsedTime: Double(currentNormalizedWordOffset) / wordsPerSecond,
                playbackRate: state == .playing ? record.narrationRate : 0
            )
        )
    }

    private func observeNarrationEvents() {
        let events = engine.events
        narrationEventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func observeIndexingUpdates() {
        let updates = indexingCoordinator.updates
        indexingUpdateTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled else { return }
                await self?.resumeAfterIndexUpdate(update)
            }
        }
    }

    private func installRemoteCommands() {
        nowPlaying.installRemoteCommands(
            NowPlayingHandlers(
                play: { [weak self] in
                    guard let self, let bookID = self.currentBookID else { return }
                    Task { await self.play(bookID: bookID) }
                },
                pause: { [weak self] in self?.pause() },
                toggle: { [weak self] in
                    guard let self else { return }
                    switch self.state {
                    case .playing:
                        self.pause()
                    case .paused:
                        self.resume()
                    case .stopped, .failed:
                        guard let bookID = self.currentBookID else { return }
                        Task { await self.play(bookID: bookID) }
                    case .bufferingForIndex, .preparingVoice, .seeking:
                        break
                    }
                },
                nextChapter: { [weak self] in Task { await self?.nextChapter() } },
                previousChapter: { [weak self] in Task { await self?.previousChapter() } },
                skipForward: { [weak self] in Task { await self?.seek(by: 15) } },
                skipBackward: { [weak self] in Task { await self?.seek(by: -15) } },
                changePosition: { [weak self] seconds in
                    guard let self else { return }
                    let delta = seconds - (self.nowPlayingElapsedTime())
                    Task { await self.seek(by: delta) }
                }
            )
        )
    }

    private func nowPlayingElapsedTime() -> TimeInterval {
        guard let bookID = currentBookID,
            let record = try? libraryStore.book(id: bookID)
        else { return 0 }
        return Double(currentNormalizedWordOffset) / (2.5 * max(0.5, min(record.narrationRate, 2)))
    }
}

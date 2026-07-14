# Avail macOS MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable, open-source Avail macOS app: import user-owned EPUB/text PDF books into a visible library, progressively index them, narrate locally, and optionally follow synchronized content in the approved Option B Zen view.

**Architecture:** A Swift Package provides a SwiftUI executable plus small library targets for normalized reading data, EPUB/PDF adapters, and narration. SwiftData retains lightweight library/progress records, while versioned atomic batch files hold derived reading indexes. One main-actor playback coordinator owns a replaceable narration engine and drives every window.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftData, Observation, AVFAudio, MediaPlayer, PDFKit, NaturalLanguage, CryptoKit, ZIPFoundation 0.9.20+, SwiftSoup 2.9.6+, XCTest, Swift Package Manager, macOS 14+.

## Global Constraints

- Target macOS 14 or later on Apple Silicon and Intel.
- License all original project code under MIT; core use works without networking, accounts, analytics, or content upload.
- Use offline `AVSpeechSynthesizer` voices behind `NarrationEngine`; do not add neural models, audio export, OCR, semantic search, Q&A, annotations, cloud sync, or DRM workarounds.
- Support EPUB 2/3 and selectable-text PDFs; reject encrypted EPUBs, password-protected PDFs, corrupt files, and image-only PDFs with specific user-facing errors.
- Source books live in one security-scoped, user-selected library root that defaults visually to `~/Documents/Avail`; derived indexes and SwiftData live in Application Support.
- Make a book playable after 450 ordered words commit; continue indexing without skipping text and buffer if playback catches the frontier.
- The Zen view is approved Option B: synchronized content on the left and a persistent cover/chapter/playback inspector on the right.
- Before every UI/API decision, query Context7 official Apple libraries—especially `/websites/developer_apple_swiftui`, `/websites/developer_apple_swiftdata`, and `/websites/developer_apple_design_human-interface-guidelines`. If unavailable, use current official Apple Developer docs and record the fallback.
- Prefer native SwiftUI/macOS controls, navigation, commands, semantic colors, system typography, accessibility, and appearance behavior. Any AppKit bridge must be narrow and documented.
- Follow TDD: add a focused failing test, observe the expected failure, implement the minimum behavior, rerun the focused test, then run the whole suite before committing.

---

### Task 1: Swift package app shell and open-source baseline

**Files:**
- Create: `Package.swift`
- Create: `Sources/AvailApp/AvailApp.swift`
- Create: `Sources/AvailApp/AppEnvironment.swift`
- Create: `Sources/AvailApp/UI/RootView.swift`
- Create: `Sources/AvailApp/UI/Settings/SettingsRootView.swift`
- Create: `Sources/AvailApp/Resources/Assets.xcassets/Contents.json`
- Create: `Tests/AvailAppTests/AppEnvironmentTests.swift`
- Create: `LICENSE`, `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`

**Interfaces:**
- Produces: executable product `Avail`, executable target `AvailApp`, test target `AvailAppTests`, and `@MainActor @Observable final class AppEnvironment`.
- Consumes: none.

- [ ] **Step 1: Add the package manifest and a failing environment smoke test**

Start with a macOS 14 package containing only the executable and its tests; later tasks add library targets when their first real source file exists. Use this complete manifest:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avail",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Avail", targets: ["AvailApp"])],
    targets: [
        .executableTarget(name: "AvailApp", resources: [.process("Resources")]),
        .testTarget(name: "AvailAppTests", dependencies: ["AvailApp"]),
    ]
)
```

In `AppEnvironmentTests`, assert that a newly created environment has no selected book and reports `.needsLibraryLocation`.

```swift
@MainActor
func testFreshEnvironmentNeedsLibraryLocation() {
    let subject = AppEnvironment.bootstrapForTesting()
    XCTAssertNil(subject.selectedBookID)
    XCTAssertEqual(subject.launchState, .needsLibraryLocation)
}
```

- [ ] **Step 2: Verify the smoke test fails before the app shell exists**

Run: `swift test --filter AppEnvironmentTests/testFreshEnvironmentNeedsLibraryLocation`

Expected: FAIL because `AppEnvironment` is unavailable.

- [ ] **Step 3: Implement the minimal SwiftUI app and environment**

```swift
@MainActor @Observable
final class AppEnvironment {
    enum LaunchState: Equatable { case needsLibraryLocation, loading, ready, failed(String) }
    var launchState: LaunchState
    var selectedBookID: UUID?

    init(launchState: LaunchState = .needsLibraryLocation) {
        self.launchState = launchState
    }

    static func bootstrapForTesting() -> AppEnvironment { AppEnvironment() }
}

@main
struct AvailApp: App {
    @State private var environment = AppEnvironment()
    var body: some Scene {
        WindowGroup("Avail") { RootView().environment(environment) }
        Settings { SettingsRootView().environment(environment) }
    }
}
```

Implement the initial `RootView` as a native `ContentUnavailableView` that explains library selection and the initial `SettingsRootView` as a `Form` with a disabled Library Location row. These are complete empty-state views that Task 10 and Task 12 will enrich. Add the full MIT text and concise contributor/project docs that state local-only behavior and the Context7/Apple UI policy.

- [ ] **Step 4: Run the test suite and build**

Run: `swift test && swift build`

Expected: all tests PASS; `Build complete!` for the `Avail` executable.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests LICENSE README.md CONTRIBUTING.md CODE_OF_CONDUCT.md
git commit -m "chore: scaffold Avail macOS app"
```

### Task 2: Normalized reading model and deterministic chunking

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailCore/ReadingModels.swift`
- Create: `Sources/AvailCore/DocumentIndexing.swift`
- Create: `Sources/AvailCore/TextChunker.swift`
- Create: `Tests/AvailCoreTests/TextChunkerTests.swift`
- Create: `Tests/AvailCoreTests/ReadingModelsTests.swift`

**Interfaces:**
- Produces: `BookFormat`, `BookMetadata`, `SourceLocator`, `ReadingSection`, `SpeechChunk`, `ReadingPosition`, `IndexBatch`, `IndexManifest`, `IndexingEvent`, `DocumentIndexer`, `TextChunker`.
- Consumes: Foundation and NaturalLanguage only.

Add library product/target `AvailCore`, make `AvailApp` depend on it, and add test target `AvailCoreTests` before running the failing tests.

- [ ] **Step 1: Write failing model round-trip and chunk-boundary tests**

Cover Codable round trips, stable IDs, paragraph/sentence preservation, 800–1,200 target size, 2,000 hard maximum, Unicode/emoji, CJK text, empty input, and source offsets. The core assertion is:

```swift
let chunks = TextChunker().chunks(from: input, sectionID: sectionID, locator: .epub(spineIndex: 0, href: "chapter.xhtml"))
XCTAssertEqual(chunks.map(\.text).joined(separator: " ").normalizedWhitespace, input.normalizedWhitespace)
XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 2_000 })
XCTAssertEqual(chunks.map(\.ordinal), Array(chunks.indices))
```

- [ ] **Step 2: Run focused tests and confirm type-not-found failures**

Run: `swift test --filter AvailCoreTests`

Expected: FAIL because the core types do not exist.

- [ ] **Step 3: Define exact Sendable/Codable core types**

```swift
public enum BookFormat: String, Codable, Sendable { case epub, pdf }
public enum SourceLocator: Codable, Hashable, Sendable {
    case epub(spineIndex: Int, href: String)
    case pdf(pageIndex: Int)
}
public struct BookMetadata: Codable, Equatable, Sendable {
    public var title: String
    public var authors: [String]
    public var languageCode: String?
    public var coverData: Data?
}
public struct ReadingSection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let ordinal: Int
    public let title: String?
    public let locator: SourceLocator
    public let chunkIDs: [UUID]
}
public struct SpeechChunk: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let sectionID: UUID
    public let ordinal: Int
    public let text: String
    public let wordCount: Int
    public let locator: SourceLocator
}
public struct ReadingPosition: Codable, Equatable, Sendable {
    public let bookID: UUID
    public var sectionID: UUID
    public var chunkID: UUID
    public var utf16Offset: Int
    public var normalizedWordOffset: Int
    public var updatedAt: Date
}
public struct IndexBatch: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let sections: [ReadingSection]
    public let chunks: [SpeechChunk]
    public let resumeLocator: SourceLocator
}
public struct IndexManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var batchFiles: [String]
    public var indexedWordCount: Int
    public var playableFrontier: SourceLocator?
    public var isComplete: Bool
}
public enum IndexingPhase: String, Codable, Sendable {
    case waiting, readingMetadata, indexing, playable, complete, failed
}
public struct IndexingProgress: Codable, Equatable, Sendable {
    public var phase: IndexingPhase
    public var completedSourceUnits: Int
    public var totalSourceUnits: Int?
    public var indexedWordCount: Int
    public var playableFrontier: SourceLocator?
    public var errorDescription: String?
}
public enum IndexingEvent: Sendable {
    case metadata(BookMetadata)
    case batch(IndexBatch)
    case completed(totalWords: Int, sectionCount: Int)
}
public protocol DocumentIndexer: Sendable {
    func events(for fileURL: URL, bookID: UUID, resumeAfter: SourceLocator?) -> AsyncThrowingStream<IndexingEvent, Error>
}
```

Define `BookFormat`, `SourceLocator`, `BookMetadata`, `ReadingSection`, `SpeechChunk`, `ReadingPosition`, `IndexBatch`, `IndexManifest`, `IndexingPhase`, `IndexingProgress`, and `IndexingEvent` exactly as shown, adding public memberwise initializers. Generate stable section/chunk UUIDs from SHA-256 of the persistent book ID plus source locator and ordinal so rebuilding preserves identity.

- [ ] **Step 4: Implement sentence-aware `TextChunker`**

Use paragraph splitting first and `NLTokenizer(unit: .sentence)` second. Accumulate until at least 800 characters, prefer ending by 1,200, and split at the final whitespace before 2,000. Count words with `NLTokenizer(unit: .word)` so scripts without spaces remain playable.

- [ ] **Step 5: Run core tests and commit**

Run: `swift test --filter AvailCoreTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailCore Tests/AvailCoreTests
git commit -m "feat: add normalized reading model"
```

### Task 3: Atomic progressive reading-index storage

**Files:**
- Create: `Sources/AvailCore/ReadingIndexStore.swift`
- Create: `Sources/AvailCore/AtomicFileWriter.swift`
- Create: `Tests/AvailCoreTests/ReadingIndexStoreTests.swift`

**Interfaces:**
- Consumes: `IndexBatch`, `IndexManifest`, `SpeechChunk`, `ReadingPosition` from Task 2.
- Produces: `actor ReadingIndexStore` with `prepare(bookID:)`, `commit(_:bookID:)`, `manifest(bookID:)`, `chunks(bookID:around:limit:)`, `position(bookID:normalizedWordOffset:)`, `discard(bookID:)`, and `recover(bookID:)`.

- [ ] **Step 1: Write failing tests for atomic commits and recovery**

Use a unique temporary directory. Assert a 50-chunk batch becomes visible only after manifest replacement, `.tmp` residue is ignored, repeated commit is idempotent, cancellation leaves the prior frontier, schema mismatch invalidates derived data, and word-offset lookup returns the nearest sentence chunk.

```swift
let store = ReadingIndexStore(rootURL: temporaryDirectory)
try await store.prepare(bookID: bookID)
try await store.commit(batch, bookID: bookID)
let manifest = try await store.manifest(bookID: bookID)
XCTAssertEqual(manifest.indexedWordCount, batch.chunks.reduce(0) { $0 + $1.wordCount })
```

- [ ] **Step 2: Verify tests fail, then implement versioned batch files**

Run: `swift test --filter ReadingIndexStoreTests`

Expected: FAIL because `ReadingIndexStore` is unavailable.

Store `manifest.json` and `batch-000000.json` files under `<root>/<book UUID>/`. Encode to a sibling `.tmp`, call `FileHandle.synchronize()`, then use `FileManager.replaceItemAt` or move for first creation. `recover` removes only `.tmp` files and batches absent from the manifest. Use `schemaVersion = 1`.

- [ ] **Step 3: Pass focused and full suites, then commit**

Run: `swift test --filter ReadingIndexStoreTests && swift test`

Expected: all tests PASS.

```bash
git add Sources/AvailCore Tests/AvailCoreTests/ReadingIndexStoreTests.swift
git commit -m "feat: persist progressive reading indexes"
```

### Task 4: EPUB 2/3 indexing adapter

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailEPUB/EPUBIndexer.swift`
- Create: `Sources/AvailEPUB/EPUBPackageParser.swift`
- Create: `Sources/AvailEPUB/EPUBContentParser.swift`
- Create: `Sources/AvailEPUB/EPUBError.swift`
- Create: `Tests/AvailEPUBTests/EPUBIndexerTests.swift`
- Create: `Tests/AvailEPUBTests/Fixtures/` with hand-authored minimal EPUB fixtures generated by the test target.

**Interfaces:**
- Consumes: `DocumentIndexer`, `IndexingEvent`, `TextChunker`, and normalized types from `AvailCore`.
- Produces: `public struct EPUBIndexer: DocumentIndexer` and typed `EPUBError` cases `invalidContainer`, `missingPackage`, `encrypted`, `emptySpine`, `unreadableContent`.

Add the `ZIPFoundation` and `SwiftSoup` package dependencies at the verified minimum versions, library product/target `AvailEPUB` depending on `AvailCore`, `ZIPFoundation`, and `SwiftSoup`, and test target `AvailEPUBTests`.

- [ ] **Step 1: Create failing package/parser stream tests**

Generate zipped fixtures during tests for EPUB 2 NCX, EPUB 3 nav, nested XHTML, malformed HTML, missing metadata, empty spine item, and `META-INF/encryption.xml`. Assert metadata event precedes batch events, batch order matches OPF spine, scripts/styles are absent, cover bytes are returned when declared, and encrypted content throws `.encrypted`.

- [ ] **Step 2: Run the focused tests and observe failures**

Run: `swift test --filter AvailEPUBTests`

Expected: FAIL because `EPUBIndexer` is unavailable.

- [ ] **Step 3: Implement safe package and XHTML parsing**

Use `ZIPFoundation.Archive` without extracting untrusted paths to disk. Resolve `META-INF/container.xml`, parse OPF metadata/manifest/spine with `XMLParser`, reject encrypted entries, and parse each spine XHTML document with SwiftSoup. Preserve headings and paragraph/list-item boundaries; ignore `script`, `style`, `nav[epub:type=landmarks]`, hidden content, and blank nodes.

Emit batches no larger than 50 chunks and include the final source locator in every event so interrupted indexing resumes after the last committed spine item.

- [ ] **Step 4: Pass tests and commit**

Run: `swift test --filter AvailEPUBTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailEPUB Tests/AvailEPUBTests
git commit -m "feat: index EPUB books"
```

### Task 5: Selectable-text PDF indexing adapter

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailPDF/PDFIndexer.swift`
- Create: `Sources/AvailPDF/PDFMetadataReader.swift`
- Create: `Sources/AvailPDF/PDFIndexingError.swift`
- Create: `Tests/AvailPDFTests/PDFIndexerTests.swift`

**Interfaces:**
- Consumes: `DocumentIndexer`, `IndexingEvent`, `TextChunker`, normalized types from `AvailCore`, and Apple `PDFKit`.
- Produces: `public struct PDFIndexer: DocumentIndexer`; `PDFIndexingError` cases `unreadable`, `locked`, `noSelectableText`, `cancelled`.

Add library product/target `AvailPDF` depending on `AvailCore` and test target `AvailPDFTests`.

- [ ] **Step 1: Write failing PDF page-order and rejection tests**

Create small PDFs in tests with `CGContext`/Core Text: multi-page selectable text, outline/no outline, empty page, and image-only page. Assert events arrive page-by-page, section titles use outline labels when available and `Page N` otherwise, empty pages are skipped, and documents with no meaningful text after sampling up to the first 10 pages throw `.noSelectableText`.

- [ ] **Step 2: Run tests and observe missing adapter failure**

Run: `swift test --filter AvailPDFTests`

Expected: FAIL because `PDFIndexer` is unavailable.

- [ ] **Step 3: Implement bounded page extraction**

Initialize `PDFDocument(url:)`, reject `isLocked`, extract `page.string` one page at a time inside an autorelease pool, and release page text after chunk emission. Never call whole-document `PDFDocument.string`. Treat pages in PDF order as authoritative and document the multi-column limitation in the error/help copy.

- [ ] **Step 4: Pass tests and commit**

Run: `swift test --filter AvailPDFTests && swift test`

Expected: all tests PASS with bounded page extraction.

```bash
git add Package.swift Sources/AvailPDF Tests/AvailPDFTests
git commit -m "feat: index selectable-text PDFs"
```

### Task 6: SwiftData library and security-scoped folder management

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailApp/Library/LibraryBookRecord.swift`
- Create: `Sources/AvailApp/Library/LibraryLocationStore.swift`
- Create: `Sources/AvailApp/Library/LibraryStore.swift`
- Create: `Sources/AvailApp/Library/LibraryError.swift`
- Create: `Tests/AvailAppTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `BookFormat`, `ReadingPosition`, SwiftData, CryptoKit.
- Produces: SwiftData `@Model final class LibraryBookRecord`; `@MainActor final class LibraryStore`; `LibraryLocationStore` with `select(_:)`, `resolve()`, `clear()`.

Ensure the `AvailApp` executable target depends on `AvailCore` before adding persistence code.

- [ ] **Step 1: Add failing in-memory SwiftData library tests**

Create `ModelContainer(for: LibraryBookRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`. Test SHA-256 duplicate focusing, collision-safe file copy, file-resource/size/date fast rescan, fingerprint rename reconciliation, external additions, missing-file state, remove-record-only, move-to-Trash delegation, and failed relocation rollback.

- [ ] **Step 2: Run focused tests and confirm failures**

Run: `swift test --filter LibraryStoreTests`

Expected: FAIL because persistence and folder types are unavailable.

- [ ] **Step 3: Implement the model and folder bookmark lifecycle**

```swift
@Model final class LibraryBookRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var fingerprint: String
    var relativePath: String
    var title: String
    var author: String?
    var formatRawValue: String
    var stateRawValue: String
    var indexedWordCount: Int
    var sectionID: UUID?
    var chunkID: UUID?
    var utf16Offset: Int
    var normalizedWordOffset: Int
    var voiceIdentifier: String?
    var rate: Double
}
```

Create security-scoped bookmark data with `.withSecurityScope`, persist it in `UserDefaults`, balance every successful `startAccessingSecurityScopedResource()` with `stopAccessing...`, and surface `.needsReconnect` rather than silently picking a new directory.

- [ ] **Step 4: Implement import, scan, relocate, and removal semantics**

Copy through a temporary destination followed by atomic rename. Compute SHA-256 by streaming 1 MiB blocks. On exact duplicate, delete only the temporary import and return the existing ID. Relocation copies all files, verifies count/size/fingerprint, switches the bookmark, then moves the old managed copies to Trash only after success.

- [ ] **Step 5: Pass tests and commit**

Run: `swift test --filter LibraryStoreTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailApp/Library Tests/AvailAppTests/LibraryStoreTests.swift
git commit -m "feat: manage the visible book library"
```

### Task 7: Progressive indexing coordinator and recovery

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailApp/Indexing/IndexingCoordinator.swift`
- Create: `Sources/AvailApp/Indexing/IndexerFactory.swift`
- Create: `Tests/AvailAppTests/IndexingCoordinatorTests.swift`

**Interfaces:**
- Consumes: `LibraryStore`, `ReadingIndexStore`, `DocumentIndexer`, EPUB/PDF adapters.
- Produces: `@MainActor @Observable final class IndexingCoordinator` with `start(bookID:)`, `cancel(bookID:)`, `prioritize(bookID:after:)`, `retry(bookID:)`, and per-book `IndexingProgress`.

Add `AvailEPUB` and `AvailPDF` to the `AvailApp` executable target dependencies.

- [ ] **Step 1: Write failing progressive-readiness tests with fake streams**

Feed metadata plus 200-word, 300-word, and completion events. Assert the book remains indexing after 200 words, becomes playable at 500 committed words, persists each frontier before UI state changes, resumes after the last locator on restart, and prioritizes a seek beyond the frontier. Simulate disk-full and cancellation errors and verify specific retryable states.

- [ ] **Step 2: Run tests and observe missing coordinator failure**

Run: `swift test --filter IndexingCoordinatorTests`

Expected: FAIL because `IndexingCoordinator` is unavailable.

- [ ] **Step 3: Implement one cancellable task per book**

Select indexers by file signature plus extension, commit every event to `ReadingIndexStore`, then update SwiftData on the main actor. Mark playable at `indexedWordCount >= 450`. Persist the source locator only after an index batch commit. Use task priorities to favor the active book and cancellation checks between every source unit.

- [ ] **Step 4: Pass tests and commit**

Run: `swift test --filter IndexingCoordinatorTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailApp/Indexing Tests/AvailAppTests/IndexingCoordinatorTests.swift
git commit -m "feat: coordinate progressive book indexing"
```

### Task 8: Replaceable local narration engine

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailPlayback/NarrationModels.swift`
- Create: `Sources/AvailPlayback/NarrationEngine.swift`
- Create: `Sources/AvailPlayback/SystemNarrationEngine.swift`
- Create: `Tests/AvailPlaybackTests/SystemNarrationEngineTests.swift`

**Interfaces:**
- Consumes: `SpeechChunk` from `AvailCore`, `AVSpeechSynthesizer` and delegate callbacks from AVFAudio.
- Produces: `NarrationVoice`, `NarrationRequest`, `NarrationEvent`, `@MainActor protocol NarrationEngine`, `@MainActor final class SystemNarrationEngine`.

Add library product/target `AvailPlayback` depending on `AvailCore` and test target `AvailPlaybackTests`.

- [ ] **Step 1: Write failing engine-contract tests using an injected synthesizer seam**

Assert voice filtering by BCP-47 language, system fallback, utterance rate/voice assignment, pause/continue/stop forwarding, retained synthesizer lifetime, and delegate mapping for didStart/willSpeakRange/didPause/didContinue/didFinish/didCancel.

```swift
@MainActor protocol NarrationEngine: AnyObject {
    var voices: [NarrationVoice] { get }
    var events: AsyncStream<NarrationEvent> { get }
    func speak(_ request: NarrationRequest)
    func pause()
    func resume()
    func stop()
}
```

- [ ] **Step 2: Run tests and confirm contract failure**

Run: `swift test --filter AvailPlaybackTests`

Expected: FAIL because narration types do not exist.

- [ ] **Step 3: Implement the AVSpeechSynthesizer adapter**

Retain one synthesizer instance, associate utterances with chunk IDs, emit UTF-16 `NSRange` values unchanged, and call `pauseSpeaking(at: .word)` / `stopSpeaking(at: .immediate)`. Use only installed `AVSpeechSynthesisVoice.speechVoices()` entries and expose a fallback event when the saved identifier is missing.

- [ ] **Step 4: Pass tests and commit**

Run: `swift test --filter AvailPlaybackTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailPlayback Tests/AvailPlaybackTests
git commit -m "feat: add local system narration engine"
```

### Task 9: Single-session playback coordination and progress persistence

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AvailApp/Playback/PlaybackCoordinator.swift`
- Create: `Sources/AvailApp/Playback/PlaybackPersistence.swift`
- Create: `Sources/AvailApp/Playback/NowPlayingController.swift`
- Create: `Tests/AvailAppTests/PlaybackCoordinatorTests.swift`
- Create: `Tests/AvailAppTests/NowPlayingControllerTests.swift`

**Interfaces:**
- Consumes: `NarrationEngine`, `ReadingIndexStore`, `LibraryStore`, `IndexingCoordinator`, MediaPlayer.
- Produces: application-wide `@MainActor @Observable final class PlaybackCoordinator`; `NowPlayingController` wrapping `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.

Add `AvailPlayback` to the `AvailApp` executable target dependencies.

- [ ] **Step 1: Write failing coordinator tests with a fake narration engine**

Cover play/pause/resume, automatic next chunk, one active book, debounced range persistence plus immediate persistence on pause/stop/seek/terminate, word-offset fallback after index rebuild, approximate ±15-second sentence seeking, chapter navigation over empty sections, frontier buffering/resume, missing voice fallback, and follow-mode highlight updates.

- [ ] **Step 2: Run tests and observe failures**

Run: `swift test --filter PlaybackCoordinatorTests`

Expected: FAIL because `PlaybackCoordinator` is unavailable.

- [ ] **Step 3: Implement the playback state machine**

Use states `.stopped`, `.bufferingForIndex`, `.playing`, `.paused`, `.seeking`, `.failed(String)`. Convert 15 seconds to a word delta from the selected speech rate and land at the nearest chunk/sentence boundary. Queue at most two chunks. On a frontier miss, stop narration, request indexing priority, enter buffering, and resume from the exact cursor after commit.

- [ ] **Step 4: Implement native Now Playing and remote commands**

Populate title, artist, chapter, artwork, estimated duration/elapsed time, playback rate, and `MPNowPlayingInfoCenter.default().playbackState` on macOS. Register play, pause, toggle, next/previous chapter, skip forward/backward intervals of 15, and change-position handlers. Remove all command targets during teardown to prevent duplicates.

- [ ] **Step 5: Pass tests and commit**

Run: `swift test --filter PlaybackCoordinatorTests && swift test --filter NowPlayingControllerTests && swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AvailApp/Playback Tests/AvailAppTests
git commit -m "feat: coordinate audiobook playback"
```

### Task 10: Native library UI and first-run folder flow

**Files:**
- Create: `Sources/AvailApp/UI/Library/LibraryRootView.swift`
- Create: `Sources/AvailApp/UI/Library/LibrarySidebar.swift`
- Create: `Sources/AvailApp/UI/Library/LibraryGridView.swift`
- Create: `Sources/AvailApp/UI/Library/BookCardView.swift`
- Create: `Sources/AvailApp/UI/Library/LibraryLocationView.swift`
- Create: `Sources/AvailApp/UI/Components/BookStateLabel.swift`
- Modify: `Sources/AvailApp/AvailApp.swift`
- Modify: `Sources/AvailApp/AppEnvironment.swift`
- Modify: `Sources/AvailApp/UI/RootView.swift`
- Create: `Tests/AvailAppTests/LibraryViewModelTests.swift`

**Interfaces:**
- Consumes: library/indexing/playback services and SwiftData query results.
- Produces: HIG-native `NavigationSplitView` library, first-run/reconnect folder flow, commands for Import and playback.

- [ ] **Step 1: Re-query Context7 and record UI sources**

Query `/websites/developer_apple_swiftui` for macOS `NavigationSplitView`, `fileImporter`, commands, accessibility, and scene restoration; query `/websites/developer_apple_design_human-interface-guidelines` for sidebars, toolbars, selection, progress, empty states, and keyboard behavior. Add source URLs and decisions to `docs/ui-guidance.md`.

- [ ] **Step 2: Write failing view-model tests**

Test first-run `.needsLibraryLocation`, reconnect without silent fallback, native import action availability, state-to-label/icon mapping that does not rely on color, Continue Listening selection, and disabled Play before 450 words.

- [ ] **Step 3: Implement the library with native patterns**

Use `NavigationSplitView` for collection filters and detail/grid content; `ContentUnavailableView` for no library/no books; `fileImporter` with EPUB/PDF UTTypes; `ProgressView` for copy/indexing; semantic colors; standard context menus; and `OpenWindowAction` for Zen. The first-run folder picker suggests Documents/Avail but requires user confirmation.

- [ ] **Step 4: Add commands and accessibility**

Add Command–O Import, Space play/pause when the library selection is focused, toolbar Import/Play/Open Zen actions, explicit accessibility labels/values, Full Keyboard Access order, Reduce Motion-aware transitions, light/dark previews, and minimum window size without fixed maximum size.

- [ ] **Step 5: Run tests/build and commit**

Run: `swift test --filter LibraryViewModelTests && swift test && swift build`

Expected: all tests PASS and app builds.

```bash
git add Sources/AvailApp/UI Sources/AvailApp/AvailApp.swift Sources/AvailApp/AppEnvironment.swift Tests/AvailAppTests docs/ui-guidance.md
git commit -m "feat: build the native library experience"
```

### Task 11: Approved Option B Zen view and synchronized highlighting

**Files:**
- Create: `Sources/AvailApp/UI/Zen/ZenReaderView.swift`
- Create: `Sources/AvailApp/UI/Zen/ReadingContentView.swift`
- Create: `Sources/AvailApp/UI/Zen/PlaybackInspectorView.swift`
- Create: `Sources/AvailApp/UI/Zen/ChapterMenu.swift`
- Create: `Sources/AvailApp/UI/Zen/VoiceAndRateControls.swift`
- Create: `Sources/AvailApp/UI/Zen/ZenViewModel.swift`
- Modify: `Sources/AvailApp/AvailApp.swift`
- Create: `Tests/AvailAppTests/ZenViewModelTests.swift`

**Interfaces:**
- Consumes: `PlaybackCoordinator`, `ReadingIndexStore`, `LibraryStore`, `OpenWindowAction`.
- Produces: `WindowGroup(id: "zen", for: UUID.self)` containing approved Option B layout; follow-mode/read-along behavior.

- [ ] **Step 1: Re-query Context7 and append inspector/reading guidance**

Query official SwiftUI and HIG libraries for macOS inspectors/split views, window sizing/restoration, long-form typography, focus, Reduce Motion, and highlighted text accessibility. Record the selected native APIs in `docs/ui-guidance.md` before writing views.

- [ ] **Step 2: Write failing Zen view-model tests**

Assert highlighted UTF-16 range maps to the active chunk, automatic follow remains active until manual scroll, manual scroll exposes Return to Narration, returning re-centers without animation under Reduce Motion, closing the window preserves playback, reopening reconnects, and voice/rate persist per book.

- [ ] **Step 3: Implement Option B exactly**

Use a two-column `HSplitView`: flexible synchronized content on the left; a persistent 280-point minimum-width playback inspector on the right. Do not replace it with a listening dashboard, floating mini-player, or dark custom Zen theme. Render system serif book text, semantic spoken-range emphasis, chapter headings, and a Return to Narration overlay only when follow mode is suspended.

- [ ] **Step 4: Implement native controls and shortcuts**

Inspector order is cover, title/author, chapter, play controls, scrubber/time estimate, rate, then voice. Use standard buttons, slider, picker/menu, help text, accessibility actions, and focus rings. Add Space play/pause, Command–Left/Right approximate seek, and Option–Left/Right chapter navigation through SwiftUI `Commands` and focused values.

- [ ] **Step 5: Run tests/build and commit**

Run: `swift test --filter ZenViewModelTests && swift test && swift build`

Expected: all tests PASS and the Zen window builds.

```bash
git add Sources/AvailApp/UI/Zen Sources/AvailApp/AvailApp.swift Tests/AvailAppTests/ZenViewModelTests.swift docs/ui-guidance.md
git commit -m "feat: add the Option B Zen listening view"
```

### Task 12: Settings, privacy, failure recovery, and end-to-end acceptance

**Files:**
- Modify: `Sources/AvailApp/UI/Settings/SettingsRootView.swift`
- Create: `Sources/AvailApp/UI/Settings/LibrarySettingsView.swift`
- Create: `Sources/AvailApp/UI/Settings/PrivacyView.swift`
- Create: `Sources/AvailApp/UI/Settings/LicensesView.swift`
- Create: `Sources/AvailApp/UI/Components/RecoveryView.swift`
- Create: `Tests/AvailAppTests/RecoveryPresentationTests.swift`
- Create: `Tests/AvailAppTests/EndToEndAcceptanceTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: all services and typed errors.
- Produces: user-facing recovery mapping, library relocation UI, privacy/license views, representative end-to-end test.

- [ ] **Step 1: Write failing recovery-copy mapping tests**

Assert distinct titles, explanations, and actions for bookmark reconnect, unsupported type, corrupt EPUB, DRM/encryption, locked PDF, scanned PDF, missing source, disk full, index interruption, frontier buffering, and voice disappearance. Test that destructive file removal always routes through Trash and requires confirmation.

- [ ] **Step 2: Implement native settings and recovery views**

Use `Form`, `LabeledContent`, standard alerts/confirmation dialogs, and `ContentUnavailableView`. Library Settings reveals or relocates the managed folder. Privacy states that speech/documents stay local and that Now Playing metadata is shared with macOS only while playback is active. Licenses includes MIT notices for ZIPFoundation and SwiftSoup.

- [ ] **Step 3: Add representative end-to-end tests**

With temporary library/Application Support directories and fake narration, import a generated EPUB and 300-page PDF fixture, observe playability at 450 words before completion, start playback, advance ranges, force coordinator reconstruction, resume without duplicate/skip, disable networking assumptions, and verify no network client exists in production targets.

- [ ] **Step 4: Run all tests and inspect the app manually**

Run: `swift test --parallel && swift build -c release`

Expected: all tests PASS and release build completes.

Run the debug executable and verify first-run folder choice, import, progressive readiness, library play, Option B Zen layout, follow suspension/restoration, light/dark mode, Reduce Motion, keyboard-only controls, and VoiceOver labels.

- [ ] **Step 5: Commit**

```bash
git add Sources/AvailApp/UI/Settings Sources/AvailApp/UI/Components Tests/AvailAppTests README.md
git commit -m "feat: complete Avail MVP recovery and settings"
```

### Task 13: App bundle packaging, CI, and release documentation

**Files:**
- Create: `Packaging/Info.plist`
- Create: `Packaging/Avail.entitlements`
- Create: `Scripts/package-app.sh`
- Create: `Scripts/notarize.sh`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/pull_request_template.md`
- Create: `docs/releasing.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: release `Avail` executable and processed resources.
- Produces: `dist/Avail.app`, CI validation, documented optional signing/notarization pipeline.

- [ ] **Step 1: Write a package smoke-check script and observe failure**

Create `Scripts/verify-app.sh` that checks bundle identifier `org.openavail.Avail`, minimum system version `14.0`, executable presence, sandbox entitlement, document types for `epub`/`pdf`, and absence of quarantine on locally built output. Run before packaging and expect failure because `dist/Avail.app` does not exist.

- [ ] **Step 2: Implement deterministic app assembly**

`Scripts/package-app.sh` runs `swift build -c release --arch arm64` or the requested architecture, creates `Contents/MacOS`, `Contents/Resources`, copies the executable/resources and Info.plist, then signs ad hoc by default or with `$DEVELOPER_ID_APPLICATION` when supplied. Entitlements enable App Sandbox and user-selected read/write file access; do not add outgoing network entitlement.

- [ ] **Step 3: Add CI and release workflows**

CI resolves dependencies, runs `swift test --parallel`, release build, `Scripts/package-app.sh`, `Scripts/verify-app.sh`, and checks formatting in non-rewrite mode. Release workflow is tag-triggered, uses repository secrets for Developer ID/notary credentials, produces a universal app from arm64/x86_64 builds, notarizes, staples, zips, and attaches checksums plus license notices.

- [ ] **Step 4: Verify locally and document release procedure**

Run: `bash Scripts/package-app.sh && bash Scripts/verify-app.sh && swift test`

Expected: `dist/Avail.app` passes bundle/entitlement checks and all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Packaging Scripts .github docs/releasing.md README.md
git commit -m "build: package and validate Avail releases"
```

### Task 14: Final MVP verification and release-candidate tag readiness

**Files:**
- Modify only when a verified defect requires it; otherwise no source changes.
- Create: `docs/verification/2026-07-14-mvp.md`

**Interfaces:**
- Consumes: complete application and test suite.
- Produces: evidence-backed verification record; no tag or push without explicit release authorization.

- [ ] **Step 1: Run clean verification**

Run: `swift package clean && swift package resolve && swift test --parallel && swift build -c release && bash Scripts/package-app.sh --clean && bash Scripts/verify-app.sh`

Expected: dependency resolution succeeds, all tests PASS, release build succeeds, and bundle verification succeeds.

- [ ] **Step 2: Exercise acceptance fixtures and UI checklist**

Record timings/memory for representative EPUB and 300-page PDF imports; confirm 450-word playability, concurrent indexing, exact resume, frontier buffering, invalid/DRM/scanned failures, external rename/delete, relocation rollback, no-network operation, Option B layout, keyboard access, VoiceOver, light/dark, Increase Contrast, Reduce Transparency, and Reduce Motion.

- [ ] **Step 3: Review repository and privacy surface**

Run: `git diff --check && git status --short && rg -n "URLSession|Network\.framework|Analytics|Telemetry" Sources Package.swift`

Expected: clean diff/status for committed work and no production networking/analytics usage.

- [ ] **Step 4: Write and commit verification evidence**

Document exact commands, platform/Xcode version, pass counts, manual checks, known MVP limitations, and signing/notarization status in the verification file.

```bash
git add docs/verification/2026-07-14-mvp.md
git commit -m "docs: record Avail MVP verification"
```

- [ ] **Step 5: Stop before external release mutation**

Report the verified commit and remaining Developer ID/notary prerequisites. Do not push, create a GitHub repository, publish a release, or tag without explicit user authorization.

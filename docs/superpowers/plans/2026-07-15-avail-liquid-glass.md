# Avail Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Apple Music-inspired library layout with a persistent floating player, native Liquid Glass on macOS 26+, and a faithful standard-material fallback while retaining Avail's macOS 14 minimum.

**Architecture:** Keep `PlaybackCoordinator` as the single playback authority and `LibraryStore` as the book metadata boundary. Persist extracted EPUB covers in a dedicated actor, expose only local file URLs to SwiftUI, derive a small immutable playback presentation model, and isolate every macOS 26-only symbol in adaptive components. The library and Zen views compose those components without duplicating playback state or branching their full layouts by OS version.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Observation, ImageIO, XCTest, Swift Package Manager, macOS 14 deployment target with macOS 26 availability gates.

## Global Constraints

- Keep `Package.swift` at `.macOS(.v14)` and keep the packaged bundle's minimum system version at 14.0.
- Follow Context7's official SwiftUI documentation for all SwiftUI API choices. Native glass APIs are `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, and `ToolbarSpacer`, each referenced only inside `if #available(macOS 26.0, *)`.
- Liquid Glass belongs only to navigation and control surfaces. Book cards, reading text, settings content, and the Zen inspector remain content surfaces using semantic colors or standard materials.
- Preserve the existing app-wide playback session, menu commands, value-driven Zen window, Settings scene, search behavior, import flow, and local-only privacy model.
- Artwork is optional derived metadata. A corrupt or unwritable cover must never fail indexing or playback.
- Add tests before implementation in each task, observe the focused test fail for the intended reason, implement the minimum behavior, then rerun the focused and complete suites.

---

## Task 1: Persist and clean up local cover artwork

**Files:**

- Create: `Sources/AvailApp/Library/ArtworkStore.swift`
- Modify: `Sources/AvailApp/Library/LibraryStore.swift`
- Modify: `Sources/AvailApp/AppEnvironment.swift`
- Modify: `Sources/AvailApp/Indexing/IndexingCoordinator.swift`
- Modify: `Tests/AvailAppTests/LibraryStoreTests.swift`
- Modify: `Tests/AvailAppTests/IndexingCoordinatorTests.swift`
- Modify: `Tests/AvailAppTests/EndToEndAcceptanceTests.swift`
- Modify: `Tests/AvailAppTests/PlaybackCoordinatorTests.swift`
- Modify: `Tests/AvailAppTests/ZenViewModelTests.swift`
- Create: `Tests/AvailAppTests/ArtworkStoreTests.swift`

- [ ] **Step 1: Write failing artwork persistence tests**

Add tests using a valid in-memory one-pixel PNG and invalid bytes:

```swift
func testValidImageIsWrittenAndCanBeReadBack() async throws {
    let relativePath = await store.persist(validPNG, bookID: bookID)
    XCTAssertEqual(relativePath, "\(bookID.uuidString)/cover")
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.fileURL(for: relativePath))), validPNG)
}

func testInvalidReplacementPreservesExistingValidArtwork() async throws {
    let originalPath = await store.persist(validPNG, bookID: bookID)
    let replacementPath = await store.persist(Data("not an image".utf8), bookID: bookID)
    XCTAssertEqual(replacementPath, originalPath)
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.fileURL(for: originalPath))), validPNG)
}

func testRemoveDeletesPerBookArtworkDirectory() async throws {
    let relativePath = await store.persist(validPNG, bookID: bookID)
    await store.remove(bookID: bookID)
    XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.fileURL(for: relativePath)).path))
}
```

- [ ] **Step 2: Run the focused tests and confirm the missing type failure**

Run: `swift test --filter ArtworkStoreTests`

Expected: compilation fails because `ArtworkStore` does not exist.

- [ ] **Step 3: Implement the actor with decode validation and atomic writes**

Use ImageIO only as a validity boundary; keep AppKit out of persistence:

```swift
import Foundation
import ImageIO

actor ArtworkStore {
    nonisolated let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func persist(_ data: Data?, bookID: UUID) -> String? {
        let relativePath = "\(bookID.uuidString)/cover"
        let destination = rootURL.appending(path: relativePath)
        guard let data,
            CGImageSourceCreateWithData(data as CFData, nil) != nil
        else {
            return FileManager.default.fileExists(atPath: destination.path) ? relativePath : nil
        }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
            return relativePath
        } catch {
            return FileManager.default.fileExists(atPath: destination.path) ? relativePath : nil
        }
    }

    nonisolated func fileURL(for relativePath: String?) -> URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return rootURL.appending(path: relativePath)
    }

    func remove(bookID: UUID) {
        try? FileManager.default.removeItem(at: rootURL.appending(path: bookID.uuidString))
    }
}
```

- [ ] **Step 4: Integrate artwork with metadata and removal**

Require an `ArtworkStore` in `LibraryStore.init`, make `applyMetadata` asynchronous, and persist only a non-nil path:

```swift
func applyMetadata(_ metadata: BookMetadata, bookID: UUID) async throws {
    guard let record = try book(id: bookID) else { throw LibraryError.missingRecord }
    record.title = metadata.title
    record.author = metadata.authors.first
    record.languageCode = metadata.languageCode
    if let path = await artworkStore.persist(metadata.coverData, bookID: bookID) {
        record.coverRelativePath = path
    }
    record.updatedAt = Date()
    try context.save()
}

func artworkURL(for record: LibraryBookRecord) -> URL? {
    artworkStore.fileURL(for: record.coverRelativePath)
}
```

Call `await artworkStore.remove(bookID:)` from `remove`. Construct the production store beneath `Application Support/Avail/Artwork` and use sandbox artwork roots in every test fixture. Change metadata call sites to `try await`.

- [ ] **Step 5: Prove indexing stores cover paths and removal cleans files**

Extend `IndexingCoordinatorTests` with PNG cover bytes and assert that `coverRelativePath` points to readable data. Extend `LibraryStoreTests` to remove a book with artwork and assert cleanup in both removal modes.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
swift test --filter ArtworkStoreTests
swift test --filter LibraryStoreTests
swift test --filter IndexingCoordinatorTests
swift test --parallel
```

Expected: all tests pass.

Commit: `git add Sources Tests && git commit -m "feat: persist local book artwork"`

## Task 2: Expose current playback chapter and artwork

**Files:**

- Modify: `Sources/AvailApp/Playback/PlaybackCoordinator.swift`
- Modify: `Sources/AvailApp/UI/Zen/ZenViewModel.swift`
- Modify: `Tests/AvailAppTests/PlaybackCoordinatorTests.swift`
- Modify: `Tests/AvailAppTests/ZenViewModelTests.swift`

- [ ] **Step 1: Add failing playback presentation assertions**

After starting the fixture's first book, assert:

```swift
XCTAssertEqual(fixture.coordinator.currentChapterTitle, "Chapter 1")
XCTAssertEqual(fixture.coordinator.currentChapterNumber, 1)
XCTAssertEqual(fixture.nowPlaying.snapshots.last?.artworkData, fixture.coverData)
```

After `nextChapter()`, assert the title and number advance. Add a test that a failed or missing artwork file produces nil system artwork without interrupting playback.

- [ ] **Step 2: Run the focused test and confirm missing presentation state**

Run: `swift test --filter PlaybackCoordinatorTests`

Expected: compilation fails because the coordinator does not expose chapter presentation.

- [ ] **Step 3: Update coordinator state atomically with Now Playing**

Add observable read-only fields:

```swift
private(set) var currentChapterTitle: String?
private(set) var currentChapterNumber: Int?
```

In `updateNowPlaying`, resolve the section once, assign both fields, load artwork through `LibraryStore`, and pass the same values into `NowPlayingSnapshot`. Clear chapter state when selecting a new book before restore, and let an unreadable artwork URL map to nil.

- [ ] **Step 4: Make Zen consume the shared chapter value**

Replace Zen's duplicate section lookup with `playback.currentChapterTitle` when connected to the active book. Retain the local section fallback before playback begins.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --filter PlaybackCoordinatorTests
swift test --filter ZenViewModelTests
swift test --parallel
```

Expected: all tests pass.

Commit: `git add Sources Tests && git commit -m "feat: expose playback presentation state"`

## Task 3: Define testable floating-player presentation behavior

**Files:**

- Create: `Sources/AvailApp/UI/Playback/PlaybackBarPresentation.swift`
- Create: `Tests/AvailAppTests/PlaybackBarPresentationTests.swift`

- [ ] **Step 1: Write failing state-mapping tests**

Cover stopped, playing, paused, buffering, seeking, failed, and absent-book cases:

```swift
func testActiveBookKeepsPlayerVisibleAcrossResumableStates() {
    for state in [PlaybackState.stopped, .playing, .paused, .bufferingForIndex, .seeking] {
        let presentation = PlaybackBarPresentation.make(book: book, state: state, chapterTitle: "Chapter 2")
        XCTAssertNotNil(presentation)
    }
}

func testPresentationMapsTransientAndFailureStatus() {
    XCTAssertEqual(make(.bufferingForIndex)?.statusText, "Preparing the next passage…")
    XCTAssertEqual(make(.seeking)?.statusText, "Seeking…")
    XCTAssertEqual(make(.failed("Speech unavailable"))?.statusText, "Speech unavailable")
}
```

- [ ] **Step 2: Run the focused tests and confirm the missing type failure**

Run: `swift test --filter PlaybackBarPresentationTests`

Expected: compilation fails because `PlaybackBarPresentation` does not exist.

- [ ] **Step 3: Implement the immutable mapping**

The model carries strings, identifiers, progress inputs, and capability booleans only. It must not retain `PlaybackCoordinator`, create tasks, or own scrub state:

```swift
struct PlaybackBarPresentation: Equatable {
    let bookID: UUID
    let title: String
    let author: String
    let chapterTitle: String?
    let statusText: String?
    let isPlaying: Bool
    let canSeek: Bool

    static func make(
        book: LibraryBookRecord?,
        state: PlaybackState,
        chapterTitle: String?
    ) -> PlaybackBarPresentation? {
        guard let book else { return nil }
        // Map semantic state without UI framework dependencies.
    }
}
```

- [ ] **Step 4: Run tests and commit**

Run: `swift test --filter PlaybackBarPresentationTests && swift test --parallel`

Expected: all tests pass.

Commit: `git add Sources Tests && git commit -m "feat: model floating player presentation"`

## Task 4: Build the compatibility-gated Liquid Glass primitives

**Files:**

- Create: `Sources/AvailApp/UI/Components/AdaptiveGlassSurface.swift`
- Create: `Sources/AvailApp/UI/Components/AdaptiveButtonStyles.swift`
- Create: `Sources/AvailApp/UI/Library/LibraryToolbar.swift`

- [ ] **Step 1: Add the smallest availability boundaries**

Implement a container and surface whose content hierarchy is identical on every OS:

```swift
struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

struct AdaptiveGlassSurface<Content: View>: View {
    let interactive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content().glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
            } else {
                content().glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        } else {
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.separator.opacity(0.55), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: 7)
        }
    }
}
```

Add `adaptiveGlassButtonStyle()` and `adaptiveProminentButtonStyle()` view extensions that select native glass styles on macOS 26 and `.bordered`/`.borderedProminent` on earlier systems.

- [ ] **Step 2: Define availability-safe toolbar grouping**

`LibraryToolbar` keeps Import separate from Listen/Open Zen on macOS 26 with `ToolbarSpacer(.fixed)`, while the fallback uses one `ToolbarItemGroup`. Keep every action, help label, and disabled state identical.

- [ ] **Step 3: Compile against the macOS 14 deployment target and commit**

Run:

```bash
swift build
swift format lint --strict --recursive --parallel --configuration .swift-format Sources Tests
```

Expected: the package compiles with no unguarded availability diagnostics and formatting passes.

Commit: `git add Sources && git commit -m "feat: add adaptive glass components"`

## Task 5: Upgrade book artwork and content-layer cards

**Files:**

- Create: `Sources/AvailApp/UI/Components/BookArtworkView.swift`
- Modify: `Sources/AvailApp/UI/Library/BookCardView.swift`
- Modify: `Sources/AvailApp/UI/Library/LibraryGridView.swift`

- [ ] **Step 1: Implement one reusable artwork renderer**

`BookArtworkView` accepts `LibraryBookRecord`, an optional local URL, corner radius, and accessibility label. Decode with `NSImage(contentsOf:)`; otherwise show a semantic EPUB/PDF gradient and SF Symbol. Clip once, use the cover's natural 2:3 presentation, and never apply `glassEffect`.

- [ ] **Step 2: Redesign the card as a standard material content plate**

Keep the whole card as `.buttonStyle(.plain)`. Put cover and metadata inside one rounded `.thinMaterial` plate, add a subtle selected lift and accent outline, retain `BookStateLabel`, context menu, focus ring, help, and accessibility text. Selection must remain visible without relying solely on fill color.

- [ ] **Step 3: Add explicit player clearance to the grid**

Add `bottomContentInset: CGFloat` and `artworkURL: (LibraryBookRecord) -> URL?` to `LibraryGridView`. Apply the inset to the scroll content so the final row clears the overlay.

- [ ] **Step 4: Build, inspect, and commit**

Run: `swift build && swift test --parallel`

Expected: build and suite pass.

Commit: `git add Sources && git commit -m "feat: redesign artwork-led library cards"`

## Task 6: Build the responsive floating playback bar

**Files:**

- Create: `Sources/AvailApp/UI/Playback/PlaybackTransportControls.swift`
- Create: `Sources/AvailApp/UI/Playback/PlaybackProgressControl.swift`
- Create: `Sources/AvailApp/UI/Playback/FloatingPlaybackBar.swift`
- Create: `Tests/AvailAppTests/PlaybackProgressModelTests.swift`

- [ ] **Step 1: Test scrub synchronization independently of SwiftUI gestures**

Create a small `@MainActor @Observable PlaybackProgressModel` and test that coordinator updates follow while idle, are ignored while scrubbing, and emit one committed offset when editing ends:

```swift
model.synchronize(to: 120)
XCTAssertEqual(model.value, 120)
model.editingChanged(true)
model.value = 240
model.synchronize(to: 300)
XCTAssertEqual(model.value, 240)
XCTAssertEqual(model.editingChanged(false), 240)
```

- [ ] **Step 2: Run the focused test and confirm the missing model failure**

Run: `swift test --filter PlaybackProgressModelTests`

Expected: compilation fails because `PlaybackProgressModel` does not exist.

- [ ] **Step 3: Implement reusable transport and progress controls**

`PlaybackTransportControls` receives explicit closures for previous chapter, back 15 seconds, toggle, forward 15 seconds, and next chapter. Each icon-only button has matching accessibility and help text; only play/pause is prominent. `PlaybackProgressControl` owns the tested scrub model, receives current/total words and narration rate, and commits exactly one `seek` on release.

- [ ] **Step 4: Compose full and compact player layouts**

`FloatingPlaybackBar` receives the presentation, artwork URL, progress values, narration rate, and closures. Use `ViewThatFits(in: .horizontal)` to select:

- full: artwork and metadata; five transport actions; slider/times plus Open Zen;
- compact: artwork, title/status, play/pause, and Open Zen.

Wrap full-form metadata, transport, and progress groups in one `AdaptiveGlassContainer`. Apply one `AdaptiveGlassSurface` per adjacent functional group so native glass samples coherently on macOS 26 while the fallback reads as one restrained bar. Do not add volume or duplicate voice/rate controls.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
swift test --filter PlaybackProgressModelTests
swift test --filter PlaybackBarPresentationTests
swift test --parallel
```

Expected: all tests pass.

Commit: `git add Sources Tests && git commit -m "feat: add floating playback controls"`

## Task 7: Integrate the player into Library and Zen

**Files:**

- Modify: `Sources/AvailApp/UI/Library/LibraryRootView.swift`
- Modify: `Sources/AvailApp/UI/Zen/PlaybackInspectorView.swift`
- Modify: `Sources/AvailApp/UI/Zen/ReadingContentView.swift`
- Modify: `Sources/AvailApp/UI/Zen/ZenViewModel.swift`

- [ ] **Step 1: Make the library derive its player from the active session**

Match `playback.currentBookID` against the queried books, create `PlaybackBarPresentation`, and overlay `FloatingPlaybackBar` at the bottom of the detail column. Pass 118 points of grid clearance only when the presentation exists. Keep stopped sessions visible when a current chunk exists; hide stale sessions whose record is absent.

- [ ] **Step 2: Wire every action to the existing coordinator**

Use the existing `pause`, `resume`, `play`, `seek(by:)`, `seek(toNormalizedWordOffset:)`, `previousChapter`, `nextChapter`, and `openWindow(value:)` methods. The floating bar must not instantiate a second coordinator or copy playback state.

- [ ] **Step 3: Move search and adopt grouped toolbar content**

Attach `.searchable` to `NavigationSplitView`, replace the inline toolbar group with `LibraryToolbar`, and preserve Import, Listen/Pause, Open Zen, help strings, disabled logic, focused commands, and file-import behavior.

- [ ] **Step 4: Reuse transport controls in Zen**

Replace the inspector's private transport `HStack` with `PlaybackTransportControls`. Use `BookArtworkView` for its cover and keep `.regularMaterial` on the inspector content pane. Apply `adaptiveProminentButtonStyle()` to “Return to Narration,” retaining Reduce Motion behavior.

- [ ] **Step 5: Run integration tests and commit**

Run:

```bash
swift test --filter LibraryViewModelTests
swift test --filter ZenViewModelTests
swift test --filter PlaybackCoordinatorTests
swift test --parallel
```

Expected: all tests pass.

Commit: `git add Sources Tests && git commit -m "feat: integrate compatible Liquid Glass player"`

## Task 8: Verify compatibility, runtime design, and delivery

**Files:**

- Modify: `docs/superpowers/specs/2026-07-15-avail-liquid-glass-design.md`
- Create: `docs/superpowers/specs/2026-07-15-avail-liquid-glass-verification.md`

- [ ] **Step 1: Run repository hygiene and complete automated verification**

Run fresh commands:

```bash
git diff --check
swift package clean
swift package resolve
swift format lint --strict --recursive --parallel --configuration .swift-format Sources Tests
swift test --parallel
swift build -c release
bash Scripts/package-app.sh --clean
bash Scripts/verify-app.sh
```

Expected: all commands exit 0; the full suite passes; package verification reports macOS 14 minimum and valid sandbox/signing properties.

- [ ] **Step 2: Inspect macOS 26+ runtime behavior**

Run `bash script/build_and_run.sh --verify`, import a cover-bearing EPUB plus a PDF, and inspect the library and Zen windows. Verify full/compact player resizing, selection, last-row clearance, play/pause/seeks/chapters, Open Zen, search placement, toolbar grouping, artwork fallback, light/dark mode, inactive-window state, keyboard focus, Reduce Motion, Reduce Transparency, and Increase Contrast.

- [ ] **Step 3: Record evidence and finish the design status**

Change the design spec status to implemented and create the verification note with exact commands, test count, runtime OS, screenshots or observations, known environment limits for macOS 14–25 runtime testing, and confirmation that package metadata still declares 14.0.

- [ ] **Step 4: Review the diff, commit, and push**

Run:

```bash
git status --short
git diff --stat origin/feature/avail-mvp...HEAD
git log --oneline origin/feature/avail-mvp..HEAD
```

Use the required review and verification skills, resolve actionable findings, rerun affected checks, then commit:

`git add docs Sources Tests && git commit -m "docs: verify Liquid Glass interface"`

Push: `git push origin feature/liquid-glass-ui`

Expected: the remote branch advances to the verified implementation commit and the worktree is clean.

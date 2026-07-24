# Graph Report - .  (2026-07-22)

## Corpus Check
- Corpus is ~33,321 words - fits in a single context window. You may not need a graph.

## Summary
- 1221 nodes · 3043 edges · 53 communities (45 shown, 8 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 337 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Reading Index Storage|Reading Index Storage]]
- [[_COMMUNITY_System Narration Engine|System Narration Engine]]
- [[_COMMUNITY_PDF Indexing Pipeline|PDF Indexing Pipeline]]
- [[_COMMUNITY_Playback Session Coordination|Playback Session Coordination]]
- [[_COMMUNITY_Book File Handling|Book File Handling]]
- [[_COMMUNITY_EPUB Text Chunking|EPUB Text Chunking]]
- [[_COMMUNITY_Zen Reading Presentation|Zen Reading Presentation]]
- [[_COMMUNITY_Zen View Model Tests|Zen View Model Tests]]
- [[_COMMUNITY_Playback Coordinator Tests|Playback Coordinator Tests]]
- [[_COMMUNITY_Library Navigation State|Library Navigation State]]
- [[_COMMUNITY_Recovery UI Actions|Recovery UI Actions]]
- [[_COMMUNITY_EPUB Package Parsing|EPUB Package Parsing]]
- [[_COMMUNITY_Application Environment Lifecycle|Application Environment Lifecycle]]
- [[_COMMUNITY_Shared Dependency Imports|Shared Dependency Imports]]
- [[_COMMUNITY_End-to-End Acceptance Tests|End-to-End Acceptance Tests]]
- [[_COMMUNITY_Indexing Task Coordination|Indexing Task Coordination]]
- [[_COMMUNITY_Local Artwork Storage|Local Artwork Storage]]
- [[_COMMUNITY_Library Store Integration Tests|Library Store Integration Tests]]
- [[_COMMUNITY_Library Record Presentation|Library Record Presentation]]
- [[_COMMUNITY_Now Playing Controller|Now Playing Controller]]
- [[_COMMUNITY_Persistent Player Bar|Persistent Player Bar]]
- [[_COMMUNITY_Shared SwiftUI Views|Shared SwiftUI Views]]
- [[_COMMUNITY_Library Store Operations|Library Store Operations]]
- [[_COMMUNITY_Player Presentation Tests|Player Presentation Tests]]
- [[_COMMUNITY_Library Location Access|Library Location Access]]
- [[_COMMUNITY_Playback State Snapshots|Playback State Snapshots]]
- [[_COMMUNITY_Application Test Suites|Application Test Suites]]
- [[_COMMUNITY_Native UI Frameworks|Native UI Frameworks]]
- [[_COMMUNITY_Book Detail Screen|Book Detail Screen]]
- [[_COMMUNITY_Local-First Product Contract|Local-First Product Contract]]
- [[_COMMUNITY_macOS UI Acceptance Tests|macOS UI Acceptance Tests]]
- [[_COMMUNITY_Library Grid Cards|Library Grid Cards]]
- [[_COMMUNITY_Remote Command Tests|Remote Command Tests]]
- [[_COMMUNITY_Artwork Source Tests|Artwork Source Tests]]
- [[_COMMUNITY_Release Notarization Workflow|Release Notarization Workflow]]
- [[_COMMUNITY_Indexer Module Imports|Indexer Module Imports]]
- [[_COMMUNITY_Library Menu Commands|Library Menu Commands]]
- [[_COMMUNITY_Playback Progress Control|Playback Progress Control]]
- [[_COMMUNITY_Now Playing State Adapter|Now Playing State Adapter]]
- [[_COMMUNITY_Playback Transport Controls|Playback Transport Controls]]
- [[_COMMUNITY_Playback Scrubbing Model Tests|Playback Scrubbing Model Tests]]
- [[_COMMUNITY_CI Build Verification|CI Build Verification]]
- [[_COMMUNITY_Book Artwork View|Book Artwork View]]
- [[_COMMUNITY_Acceptance Now Playing Stub|Acceptance Now Playing Stub]]
- [[_COMMUNITY_Zen Now Playing Stub|Zen Now Playing Stub]]
- [[_COMMUNITY_Library Relocation Settings|Library Relocation Settings]]
- [[_COMMUNITY_Zen Menu Commands|Zen Menu Commands]]
- [[_COMMUNITY_Local Build Runner|Local Build Runner]]
- [[_COMMUNITY_Library Import Outcomes|Library Import Outcomes]]
- [[_COMMUNITY_App Bundle Verification|App Bundle Verification]]
- [[_COMMUNITY_Contributor Conduct Policy|Contributor Conduct Policy]]
- [[_COMMUNITY_Release Notarization Script|Release Notarization Script]]
- [[_COMMUNITY_Privacy-Safe Bug Fixture|Privacy-Safe Bug Fixture]]

## God Nodes (most connected - your core abstractions)
1. `LibraryBookRecord` - 67 edges
2. `PlaybackCoordinator` - 59 edges
3. `LibraryStore` - 45 edges
4. `ReadingIndexStore` - 45 edges
5. `Foundation` - 43 edges
6. `SpeechChunk` - 42 edges
7. `ZenViewModel` - 36 edges
8. `AvailCore` - 31 edges
9. `PlaybackFixture` - 31 edges
10. `SwiftUI` - 30 edges

## Surprising Connections (you probably didn't know these)
- `Offline and Privacy Guardrail` --semantically_similar_to--> `Local-Only Core Flows`  [INFERRED] [semantically similar]
  .github/pull_request_template.md → CONTRIBUTING.md
- `Automated Build and Test Verification` --semantically_similar_to--> `Build and Test Job`  [INFERRED] [semantically similar]
  docs/verification/2026-07-16-native-xcode-liquid-glass.md → .github/workflows/ci.yml
- `Public Release Artifact` --semantically_similar_to--> `Notarized Release Workflow`  [INFERRED] [semantically similar]
  docs/releasing.md → .github/workflows/release.yml
- `Local-Only Core Flows` --semantically_similar_to--> `No Production Networking or Analytics`  [INFERRED] [semantically similar]
  CONTRIBUTING.md → README.md
- `Accessible UI Verification` --semantically_similar_to--> `Accessible Semantic UI`  [INFERRED] [semantically similar]
  CONTRIBUTING.md → docs/ui-guidance.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Release Assurance Pipeline** — _github_pull_request_template_verification_checklist, _github_workflows_ci_build_test_job, docs_releasing_public_release_artifact, _github_workflows_release_release_workflow, docs_verification_2026_07_16_native_xcode_liquid_glass_automated_verification [INFERRED 0.95]
- **Local-First Privacy Boundary** — _github_issue_template_bug_report_privacy_safe_fixture, _github_pull_request_template_offline_privacy_guardrail, contributing_local_only_core, readme_local_first_book_listener, readme_no_production_networking, docs_releasing_app_sandbox_boundary [INFERRED 0.85]
- **Native Accessible Experience** — contributing_accessible_ui_verification, readme_liquid_glass_player, docs_ui_guidance_native_liquid_glass, docs_ui_guidance_accessible_semantic_ui, docs_ui_guidance_zen_window, docs_verification_2026_07_16_native_xcode_liquid_glass_playback_and_zen_continuity [INFERRED 0.85]

## Communities (53 total, 8 thin omitted)

### Community 0 - "Reading Index Storage"
Cohesion: 0.05
Nodes (60): BookDetailViewModel, String, UUID, Codable, Equatable, Hashable, Identifiable, JSONDecoder (+52 more)

### Community 1 - "System Narration Engine"
Cohesion: 0.06
Nodes (32): AVFAudio, AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, SpeechSynthesizerDriverDelegate, SpeechSynthesizerDriving, SpeechUtteranceSpec, Float (+24 more)

### Community 2 - "PDF Indexing Pipeline"
Cohesion: 0.06
Nodes (38): CGContext, DocumentIndexer, IndexingEvent, batch, completed, metadata, PDFIndexer, PDFResumePoint (+30 more)

### Community 3 - "Playback Session Coordination"
Cohesion: 0.09
Nodes (23): AnyObject, IndexingPrioritizing, NowPlayingControlling, PlaybackCoordinator, Bool, Data, Double, Duration (+15 more)

### Community 4 - "Book File Handling"
Cohesion: 0.06
Nodes (39): LibraryError, destinationInvalid, fileOperation, missingRecord, noLibraryLocation, sourceUnreadable, unsupportedFormat, String (+31 more)

### Community 5 - "EPUB Text Chunking"
Cohesion: 0.08
Nodes (23): Range, String, Int, SourceLocator, String, UUID, TextChunker, EPUBIndexer (+15 more)

### Community 6 - "Zen Reading Presentation"
Cohesion: 0.07
Nodes (25): AttributedString, ChapterMenu, PlaybackInspectorView, ReadingContentView, String, Binding, Double, String (+17 more)

### Community 7 - "Zen View Model Tests"
Cohesion: 0.08
Nodes (18): NarrationEvent, cancelled, finished, paused, resumed, started, voiceFallback, willSpeakRange (+10 more)

### Community 8 - "Playback Coordinator Tests"
Cohesion: 0.11
Nodes (12): FakeIndexingPrioritizer, FakeNarrationEngine, PlaybackCoordinatorTests, PlaybackFixture, AsyncStream, Bool, Duration, Int (+4 more)

### Community 9 - "Library Navigation State"
Cohesion: 0.07
Nodes (25): LibraryBookState, copying, failed, indexing, missing, playing, ready, LibrarySidebar (+17 more)

### Community 10 - "Recovery UI Actions"
Cohesion: 0.07
Nodes (28): DestructiveRemovalRequest, RecoveryAction, chooseAnotherFile, chooseVoice, freeDiskSpace, reconnectLibrary, removeFromLibrary, retryIndex (+20 more)

### Community 11 - "EPUB Package Parsing"
Cohesion: 0.16
Nodes (20): ContainerXMLDelegate, EPUBArchiveReader, EPUBManifestItem, EPUBPackage, EPUBPackageParser, Item, PackageXMLDelegate, Storage (+12 more)

### Community 12 - "Application Environment Lifecycle"
Cohesion: 0.11
Nodes (17): App, AppEnvironment, LaunchState, failed, loading, needsLibraryLocation, ready, Bool (+9 more)

### Community 13 - "Shared Dependency Imports"
Cohesion: 0.16
Nodes (9): SourceLocator, Bool, AvailCore, AvailPlayback, Foundation, AtomicFileWriter, Observation, PDFKit (+1 more)

### Community 14 - "End-to-End Acceptance Tests"
Cohesion: 0.13
Nodes (9): AcceptanceIndexingPrioritizer, AcceptanceNarrationEngine, AcceptanceServices, EndToEndAcceptanceTests, AsyncStream, Int, SourceLocator, URL (+1 more)

### Community 15 - "Indexing Task Coordination"
Cohesion: 0.20
Nodes (13): IndexerFactory, IndexerProviding, IndexingCoordinator, IndexingUpdate, AsyncStream, Error, Int, Never (+5 more)

### Community 16 - "Local Artwork Storage"
Cohesion: 0.15
Nodes (10): ArtworkStore, Bool, Data, String, URL, UUID, Data, ImageIO (+2 more)

### Community 17 - "Library Store Integration Tests"
Cohesion: 0.20
Nodes (5): LibraryStoreTests, ModelContainer, String, URL, UserDefaults

### Community 18 - "Library Record Presentation"
Cohesion: 0.12
Nodes (14): LibraryBookRecord, Bool, Date, Double, Int, Int64, UUID, BookStateLabel (+6 more)

### Community 19 - "Now Playing Controller"
Cohesion: 0.17
Nodes (12): MediaRemoteCommandDriver, NowPlayingController, NowPlayingInfoCenterDriving, Registration, RemoteCommandDriving, Any, String, SystemNowPlayingInfoCenter (+4 more)

### Community 20 - "Persistent Player Bar"
Cohesion: 0.15
Nodes (14): FloatingPlaybackBar, Bool, Int, String, URL, Void, LibraryPlaybackBarContext, PersistentPlayerContext (+6 more)

### Community 21 - "Shared SwiftUI Views"
Cohesion: 0.12
Nodes (11): RecoveryView, Void, CGFloat, URL, LibraryLocationView, RootView, LicensesView, String (+3 more)

### Community 22 - "Library Store Operations"
Cohesion: 0.19
Nodes (9): LibraryRemovalMode, moveFileToTrash, recordOnly, LibraryStore, Double, ModelContainer, String, UUID (+1 more)

### Community 23 - "Player Presentation Tests"
Cohesion: 0.20
Nodes (5): String, UUID, PlaybackBarPresentationTests, Date, String

### Community 24 - "Library Location Access"
Cohesion: 0.18
Nodes (8): LibraryAccessLease, LibraryLocationStore, Bool, T, URL, UserDefaults, LibraryBookAccess, URL

### Community 25 - "Playback State Snapshots"
Cohesion: 0.12
Nodes (13): NowPlayingSnapshot, Data, Double, Int, PlaybackState, bufferingForIndex, failed, paused (+5 more)

### Community 26 - "Application Test Suites"
Cohesion: 0.16
Nodes (7): AvailApp, AdaptiveChromeTests, BookImportContentTypesTests, LibraryDetailLayoutTests, PlaybackControlsViewTests, XCTest, XCTestCase

### Community 27 - "Native UI Frameworks"
Cohesion: 0.15
Nodes (8): AppKit, BookImportContentTypes, LibraryToolbar, Void, SwiftUI, ToolbarContent, UniformTypeIdentifiers, UTType

### Community 28 - "Book Detail Screen"
Cohesion: 0.21
Nodes (6): BookDetailView, Binding, Bool, Double, String, UUID

### Community 29 - "Local-First Product Contract"
Cohesion: 0.14
Nodes (16): Offline and Privacy Guardrail, Accessible UI Verification, Local-Only Core Flows, Sandbox and No-Network Entitlement Boundary, Accessible Semantic UI, System Glass with One Player Container, Browsing-Independent Persistent Player, Zen Window (+8 more)

### Community 30 - "macOS UI Acceptance Tests"
Cohesion: 0.25
Nodes (6): AvailUITests, Bool, String, TimeInterval, XCUIApplication, XCUIElement

### Community 31 - "Library Grid Cards"
Cohesion: 0.17
Nodes (8): BookCardView, Bool, URL, Void, LibraryGridView, Bool, URL, Void

### Community 32 - "Remote Command Tests"
Cohesion: 0.25
Nodes (6): NowPlayingHandlers, TimeInterval, Void, MainActor, FakeRemoteCommandDriver, NowPlayingControllerTests

### Community 33 - "Artwork Source Tests"
Cohesion: 0.20
Nodes (5): BookArtworkSource, Bool, NSImage, BookArtworkViewTests, URL

### Community 34 - "Release Notarization Workflow"
Cohesion: 0.20
Nodes (10): Notarization and Stapling, Versioned Release Artifacts and Checksums, Notarized Release Workflow, Tag and Marketing Version Validation, Notarization Credentials, Public Release Artifact, Repository Secret Storage Policy, SwiftSoup (+2 more)

### Community 35 - "Indexer Module Imports"
Cohesion: 0.31
Nodes (5): AvailEPUB, AvailPDF, CoreGraphics, CoreText, ZIPFoundation

### Community 36 - "Library Menu Commands"
Cohesion: 0.22
Nodes (9): FocusedValues, LibraryCommandActions, LibraryCommandActionsKey, LibraryCommands, Bool, Void, ZenCommandActionsKey, Commands (+1 more)

### Community 37 - "Playback Progress Control"
Cohesion: 0.24
Nodes (7): PlaybackProgressControl, Bool, Double, Duration, Int, String, Void

### Community 38 - "Now Playing State Adapter"
Cohesion: 0.31
Nodes (7): SystemNowPlayingState, paused, playing, stopped, FakeNowPlayingInfoCenter, Any, String

### Community 39 - "Playback Transport Controls"
Cohesion: 0.53
Nodes (5): PlaybackToggleButton, PlaybackTransportControls, Bool, String, Void

### Community 41 - "CI Build Verification"
Cohesion: 0.33
Nodes (6): Pull Request Verification Checklist, Build and Test Job, Universal Release Verification, Focused Failing Test First, Automated Build and Test Verification, Xcode 26-Compatible Build Definition

### Community 42 - "Book Artwork View"
Cohesion: 0.60
Nodes (4): BookArtworkView, CGFloat, URL, Color

### Community 46 - "Zen Menu Commands"
Cohesion: 0.67
Nodes (3): FocusedValues, Void, ZenCommandActions

### Community 47 - "Local Build Runner"
Cohesion: 0.83
Nodes (3): build_app(), open_app(), build_and_run.sh script

### Community 48 - "Library Import Outcomes"
Cohesion: 0.67
Nodes (3): LibraryImportResult, created, existing

## Knowledge Gaps
- **105 isolated node(s):** `needsLibraryLocation`, `loading`, `ready`, `failed`, `ImageIO` (+100 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `LibraryBookRecord` connect `Library Record Presentation` to `Reading Index Storage`, `Playback Session Coordination`, `Zen Reading Presentation`, `Library Navigation State`, `Book Artwork View`, `Application Environment Lifecycle`, `Shared Dependency Imports`, `Local Artwork Storage`, `Library Store Integration Tests`, `Persistent Player Bar`, `Shared SwiftUI Views`, `Library Store Operations`, `Player Presentation Tests`, `Library Location Access`, `Book Detail Screen`, `Library Grid Cards`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Why does `ZenViewModel` connect `Zen Reading Presentation` to `Reading Index Storage`, `System Narration Engine`, `Playback Session Coordination`, `Zen View Model Tests`, `Zen Menu Commands`, `Library Record Presentation`, `Persistent Player Bar`, `Library Store Operations`?**
  _High betweenness centrality (0.109) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Shared Dependency Imports` to `Reading Index Storage`, `System Narration Engine`, `PDF Indexing Pipeline`, `Indexer Module Imports`, `Book File Handling`, `EPUB Text Chunking`, `Artwork Source Tests`, `EPUB Package Parsing`, `Zen Menu Commands`, `Local Artwork Storage`, `Now Playing Controller`, `Persistent Player Bar`, `Library Location Access`, `Application Test Suites`?**
  _High betweenness centrality (0.092) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `LibraryBookRecord` (e.g. with `.seedUITestingLibrary()` and `.testExistingSwiftDataRecordReopensWithoutMigration()`) actually correct?**
  _`LibraryBookRecord` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `ReadingIndexStore` (e.g. with `.testCommitMakesBatchVisibleAndIsIdempotent()` and `.testMarkCompleteAndDiscard()`) actually correct?**
  _`ReadingIndexStore` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `needsLibraryLocation`, `loading`, `ready` to the rest of the system?**
  _115 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Reading Index Storage` be split into smaller, more focused modules?**
  _Cohesion score 0.05087572977481234 - nodes in this community are weakly interconnected._
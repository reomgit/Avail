# Avail macOS MVP Design

## Product summary

Avail is an MIT-licensed, open-source macOS application that turns user-owned EPUB and selectable-text PDF books into an on-device listening experience. The MVP is listening-first: users manage a visible local library, start narration before a large book finishes indexing, and optionally follow synchronized text in a focused Zen view. No document content, speech, analytics, or metadata leaves the Mac.

Success means a user can choose a library folder, import a DRM-free EPUB or text PDF, begin listening after approximately three minutes of ordered speech content is indexed, control playback like an audiobook, quit and reopen the app, and resume at the same passage.

## MVP boundaries

- Target macOS 14 or later on Apple Silicon and Intel, built with Swift 6 and SwiftUI.
- Distribute signed and notarized builds through GitHub Releases. Preserve Mac App Store compatibility where practical, but do not make App Store submission part of the MVP.
- Use offline macOS system voices through `AVSpeechSynthesizer`. A local neural model, downloadable voices, audio export, semantic embeddings, Q&A, annotations, search, OCR, DRM circumvention, and cloud sync are follow-up work.
- Support EPUB 2/3 package structure and PDFs with selectable text. Reject encrypted/DRM EPUBs and explain that image-only PDFs require future OCR support.
- Support one user-selected managed library root. Suggest `~/Documents/Avail` during first-run folder selection, but never assume sandbox access without explicit user selection.

## Experience design

### Library window

The library window is the app's home and management surface. It shows book cover, title, author, format, listening progress, and one of these states: copying, indexing, ready, currently playing, missing, or failed. It provides Import Book, Play/Continue Listening, Open Zen View, Reveal in Finder, Remove from Library, Retry Indexing, and Library Location settings. Play can start or resume narration directly from the library; opening the Zen view is optional.

Import copies supported files into the chosen library root with a collision-safe filename. Avail uses SHA-256 as the content fingerprint; an exact duplicate focuses the existing library record instead of creating another copy. Avail rescans on launch and app activation, comparing filename, file resource identifier, size, and modification date before recomputing a fingerprint. Supported files added in Finder are enrolled automatically; deleted files are marked missing rather than silently removing progress. The fingerprint reconnects renamed files to existing records.

Changing the library location performs a coordinated copy or move selected by the user, validates the destination, persists the new security-scoped bookmark only after success, and leaves the original library untouched on failure.

### Zen view — approved Option B

Opening a book uses the approved Option B layout without redesign:

- The left side is a generous, scrollable book-content surface. It follows narration and highlights the currently spoken range. Users can scroll away; a Return to Narration control restores follow mode.
- The persistent right inspector contains the cover, title, author, current chapter, play/pause, previous/next chapter, estimated 15-second back/forward, scrubber, elapsed/remaining estimates, speed, and voice.
- Narration is the primary action. The text exists as an optional read-along companion and does not need interaction for listening to continue.
- Closing or minimizing the Zen view does not stop playback. Reopening the book reconnects to the same session rather than starting another narrator.
- Support Space for play/pause, Command–Left/Right for estimated 15-second seek, Option–Left/Right for chapter navigation, system media play/pause, and Now Playing metadata where supported.

The MVP offers speed from 0.5× to 2.0× and installed system voices compatible with the book language. Voice and speed are saved per book. Remaining time is explicitly an estimate recalculated from indexed word count, selected rate, and current normalized position.

### UI design language and documentation policy

Apple's current Human Interface Guidelines and official SwiftUI documentation are the source of truth for every UI decision. Before adding or changing a SwiftUI API, macOS interaction pattern, navigation structure, window behavior, control, accessibility behavior, or visual treatment, use Context7 to resolve and query the official Apple documentation libraries. Prefer `/websites/developer_apple_swiftui` and `/websites/developer_apple_design_human-interface-guidelines`; if Context7 lacks the required page, consult the current official Apple Developer documentation and record the fallback in the implementation notes.

- Build the library with `NavigationSplitView` and the approved Zen view with native split/inspector patterns. Use SwiftUI scene and window APIs for restoration, resizing, commands, and focused values; add AppKit interop only when SwiftUI cannot provide required macOS behavior.
- Prefer standard SwiftUI controls, toolbars, menus, commands, sheets, alerts, focus behavior, and keyboard conventions. A custom playback control must retain native hit targets, focus rings, keyboard activation, accessibility roles/values/actions, and enabled/disabled behavior.
- Use semantic system colors and materials so appearance, contrast, accent color, Increase Contrast, and light/dark mode adapt automatically. Do not hard-code a proprietary theme for the MVP.
- Use system typography: the platform default for interface chrome and the system serif design for long-form book content. Respect user font-size controls, window resizing, text reflow, localization expansion, and legibility; never encode text as imagery.
- Support Full Keyboard Access, VoiceOver, Reduce Motion, Reduce Transparency, and differentiate-without-color. Spoken-range highlighting must remain understandable with color disabled and must not trigger forced scrolling when Reduce Motion or follow mode is off.
- Keep platform behavior recognizable: familiar sidebar selection, toolbar placement, inspector hierarchy, menu commands, undoable/destructive action treatment, and clear window titles. Visual novelty may refine hierarchy but never replace established macOS behavior.

Each UI pull request must identify the relevant Context7/Apple guidance in its description and include accessibility plus light/dark appearance verification. The implementation plan and code review checklist enforce this policy for the lifetime of the project.

## Architecture and interfaces

Use a native, normalized reading index as the boundary between document formats, rendering, persistence, and narration.

### Core types

- `LibraryBook`: stable ID, content fingerprint, visible file URL identity, format, metadata, cover reference, language, library/indexing state, total indexed words, and listening preferences.
- `ReadingSection`: stable ID, ordinal, title, source locator (EPUB spine item or PDF page range), and ordered chunk IDs.
- `SpeechChunk`: stable ID, section ID, ordinal, normalized text, word count, source locator, and display-range mapping needed for highlighting.
- `ReadingPosition`: book ID, section/chunk ID, UTF-16 character offset within the chunk, normalized word offset, and update timestamp.
- `IndexingProgress`: phase, completed source units, known total units when available, indexed word count, playable frontier, and optional recoverable error.
- `PlaybackState`: stopped, buffering for index, playing, paused, seeking, or failed, plus current position and active utterance range.

### Service boundaries

- `DocumentIndexer` is an async, cancellable producer of metadata and committed batches of normalized sections/chunks. `EPUBIndexer` and `PDFIndexer` are format adapters.
- `ReadingIndexStore` version-controls and atomically commits derived batches, loads content around a cursor, exposes the playable frontier, and can discard/rebuild an index without touching user progress.
- `LibraryStore` owns SwiftData metadata, the security-scoped library bookmark, file discovery, fingerprint reconciliation, and import/removal operations.
- `NarrationEngine` accepts a `SpeechChunk` and voice/rate settings, emits lifecycle and UTF-16 range events, and supports pause, resume, and stop. `SystemNarrationEngine` wraps a retained `AVSpeechSynthesizer`; a future neural engine must conform without changing the reader or library.
- `PlaybackCoordinator` is the single application-wide playback actor. It translates range callbacks into persisted positions and highlighting, keeps a small chunk queue, prioritizes indexing ahead of the cursor, and prevents simultaneous narrators.

UI models observe these services on the main actor; parsing, fingerprinting, index I/O, and PDF extraction run off the main actor. No view directly parses files, calls SwiftData, or controls `AVSpeechSynthesizer`.

## Import and progressive indexing

1. The user selects EPUB/PDF files. Avail validates extension and readable access, copies each file into the library root, fingerprints it, and creates a SwiftData record.
2. The indexer extracts metadata and then processes source order incrementally. EPUB uses `ZIPFoundation` from 0.9.20 and `SwiftSoup` from 2.9.6 to read `container.xml`, OPF metadata/spine, navigation, and XHTML while excluding scripts/styles. PDF uses `PDFKit` page text and outline data when present.
3. Text normalization preserves headings, paragraph boundaries, punctuation, and source mappings while removing repeated whitespace and non-content markup. `NLTokenizer` supplies sentence boundaries. Chunks target 800–1,200 characters, never split a word, and use a 2,000-character hard maximum except for a single unbreakable token.
4. `ReadingIndexStore` writes versioned batches of at most 50 chunks to per-book derived storage in Application Support. Each batch is written to a temporary file and atomically renamed; an atomically replaced manifest lists committed batches and the frontier. Interrupted temporary files are ignored on recovery.
5. A book becomes playable when at least 450 ordered words and its first source mapping are committed. Indexing continues concurrently and is reprioritized around the playback position after a seek. If playback reaches the frontier, state becomes `buffering for index`; narration resumes automatically after the next batch commits.
6. Index completion stores total words and section count. A future index schema version invalidates only derived files and rebuilds them from the visible library copy.

EPUB spine order is authoritative. PDF reading order uses each page's extracted string in page order; the MVP does not promise correct narration for visually complex multi-column PDFs and reports empty/image-only pages. Password-protected PDFs are rejected in the MVP with a specific explanation.

## Positioning and playback semantics

- Persist position at utterance range changes with a debounced write, immediately on pause/stop/seek/chapter change, and when the app resigns active or terminates.
- Resume from the stored chunk and character offset. If a derived index was rebuilt, map the normalized word offset to the nearest valid chunk; if the source content changed, restart the affected section and tell the user that the book changed.
- Estimated 15-second seek converts the active voice rate into a word delta, lands on the nearest sentence boundary, stops the current utterance, then starts at the new chunk/offset. The UI labels this control “15” while accessibility help describes it as approximate.
- Scrubbing uses normalized words across the currently indexed range during partial indexing and the whole book after completion. Seeking beyond the frontier moves the indexing priority and shows buffering rather than failing.
- Chapter navigation moves to the first speakable chunk in the adjacent section. Empty sections are skipped.
- The display maps the narration engine's UTF-16 range callback through the chunk source mapping and scrolls the active passage into view only while follow mode is enabled.

## Storage and privacy

- User-visible source books live only in the selected library root. Derived chunk batches, thumbnails, SwiftData, and security-scoped bookmarks live in the sandbox's Application Support directory.
- Removing a book asks whether to remove only Avail's record/derived data or also move the visible library file to Trash. Never permanently delete a source file.
- All model/speech work is local. The app has no analytics SDK, account system, network service, or content upload. Network access is unnecessary for core use.
- Add an in-app Privacy page describing local-only behavior and an Open Source Licenses view for dependencies.

## Failure and recovery behavior

- Library bookmark unavailable: show a blocking reconnect action that opens a folder picker; do not create a second empty library automatically.
- Unsupported, corrupt, DRM-protected, or empty document: keep the library entry in failed state with a specific explanation and Remove action.
- Scanned PDF: detect no meaningful selectable text after sampling and explain that OCR is not included.
- Indexing interrupted or app terminated: discard incomplete batch files and resume from the last committed source locator.
- File removed externally: retain metadata and position, mark missing, and offer Locate File or Remove Record.
- Disk full or destination unwritable: stop copying/indexing, clean temporary files, preserve the source, and present the failing path and recovery action.
- Playback reaches the index frontier: pause in buffering state and resume automatically; never skip text.
- Speech voice disappears: fall back to the system voice for the detected language, inform the user once, and preserve the previous preference for later recovery.

## Verification and acceptance

### Automated coverage

- Unit fixtures for EPUB 2/3 container, OPF, navigation, nested markup, malformed HTML, missing metadata, empty spine items, and encrypted content.
- Unit fixtures for text PDFs, outline/no-outline PDFs, empty pages, multi-page ordering, locked PDFs, and image-only PDFs.
- Chunking tests for sentence/paragraph boundaries, Unicode, emoji, right-to-left text, CJK without spaces, hard limits, stable IDs, and source-range round trips.
- Index-store tests for atomic batch commits, cancellation, crash residue, schema invalidation, partial loading, and resume from the last committed locator.
- Playback tests with a fake `NarrationEngine` for range mapping, debounced persistence, pause/resume, frontier buffering, estimated seeking, chapter skipping, voice fallback, and single-session enforcement.
- Library tests for bookmark recovery, collision-safe import, fingerprint rename matching, external additions/deletions, and failed relocation rollback.
- UI tests for first-run folder choice, import-to-playable flow, library states, Option B Zen layout, follow-mode suspension/restoration, keyboard controls, and reopening at the saved passage.

### Acceptance scenarios

- A representative EPUB and 300-page text PDF become playable after 450 words are committed without waiting for full indexing; playback continues while indexing progress advances.
- A large document indexes with bounded memory, a responsive UI, and no complete-document string retained beyond the active parsing batch.
- Force-quitting during indexing or narration recovers to the last committed batch and saved passage without duplicated or skipped committed text.
- App operation succeeds with networking disabled, and inspection confirms no document content is transmitted.
- VoiceOver can identify all playback controls and current book/chapter; keyboard-only users can import, start, pause, seek, change chapters, and return to the active passage.

## Open-source project setup

Initialize the repository with an MIT `LICENSE`, contribution guide, code of conduct, architecture-focused README, issue/PR templates, SwiftFormat or SwiftLint configuration in check-only CI, and GitHub Actions that build and test on a supported macOS/Xcode runner. Release signing/notarization uses repository secrets and is documented but is not required for contributor debug builds.

# Avail agent guide

This file applies to the entire repository. A more deeply nested `AGENTS.md` may add or override guidance only for its own subtree.

## Mission

Avail is an open-source, local-first macOS listener for user-owned EPUB and selectable-text PDF books. It indexes on the Mac, narrates with installed system voices, and can synchronize narration with a separate Zen reading window.

Optimize for a trustworthy reading and listening experience, not feature count. Preserve these product promises unless the maintainer explicitly approves a recorded change:

- Books and speech stay on the Mac.
- The library remains in a folder selected and controlled by the user.
- Core reading and narration work without networking, accounts, analytics, uploads, or cloud services.
- Playback can start after 450 committed indexed words while the remainder is prepared.
- Relaunch and index rebuilds preserve the exact spoken position, with a stable fallback when index identities change.
- Browsing, opening details, opening or closing Zen, and changing windows do not interrupt the active narration session.
- The first narration provider uses installed macOS voices through the pluggable `NarrationEngine` boundary.
- The current product is macOS 26+ with Swift 6. OCR, DRM-protected or encrypted EPUBs, non-macOS platforms, and cloud narration are outside the MVP.

The only deliberate metadata handoff is to macOS Now Playing during active playback. Keep that disclosure narrow and user-visible.

## Sources of truth

Use current, tracked sources in this order:

1. The user's current request and any explicitly approved product decision.
2. This file.
3. `README.md` for the product contract, supported scope, and build entry points.
4. `docs/ui-guidance.md` for dated, source-backed UI decisions.
5. `CONTRIBUTING.md` and `.github/pull_request_template.md` for contribution and verification gates.
6. `docs/releasing.md`, `.github/workflows/ci.yml`, and `.github/workflows/release.yml` for CI and release behavior.
7. `Avail.xcodeproj`, its shared `Avail` scheme, tests, and implementation for executable truth.

There is no current standalone design specification. Do not rely on the stale reference to one in `CONTRIBUTING.md`, deleted planning files, or historical specs from Git history. Files under `docs/verification/` are dated evidence snapshots, not permanent guarantees; rerun the current scheme before making a current claim.

When requirements conflict, surface the conflict with file-and-line evidence. Do not silently choose whichever source is most convenient.

## Required tools and working style

### Project knowledge graph

Use [$graphify](/Users/reom/.codex/skills/graphify/SKILL.md) for questions about project content, architecture, dependencies, ownership, file relationships, or change impact.

1. Check for `graphify-out/graph.json` before manually reconstructing the architecture.
2. If it exists, run `graphify query "<question>"` first and use source locations from the result.
3. Use `graphify path` for connection tracing and `graphify explain` for a focused concept.
4. Rebuild or update the graph only through the Graphify workflow. Never hand-edit `graphify-out/`.
5. Treat graph edges by their recorded confidence. Never present an inferred or ambiguous edge as an extracted fact.

Graphify output is generated working data. Do not stage, commit, delete, or broadly rewrite it unless the user explicitly asks.

### UI control

When a task requires operating or inspecting Xcode, Avail, Finder, System Settings, or another Mac UI, always use [@Computer](plugin://computer-use@openai-bundled). Never invoke the legacy `computer-use:computer-use` skill or its local `SKILL.md` directly. If `@Computer` is unavailable, report that limitation rather than silently falling back to the legacy skill.

Prefer deterministic CLI commands for builds, tests, formatting, logs, and file inspection. Use `@Computer` for interaction or visual/manual QA that a CLI cannot faithfully perform. Re-read the current UI state after each action and honor any confirmation required for consequential actions.

### Planning and review helpers

Use the installed workflow skills selectively:

- `/office-hours` when demand, user pain, or the narrowest wedge is unclear.
- `/plan-ceo-review` before a high-impact product or roadmap bet.
- `/plan-eng-review` for a multi-module plan, data migration, or architectural change.
- `/review` before landing a non-trivial change.
- `/ship` only when the user explicitly asks to commit, push, or open a pull request.

Skills support judgment; they do not replace repository evidence, product approval, or verification.

## Product-management operating contract

### Before building a material capability

Open or reference an issue/decision record for large product or architecture changes. Capture, at minimum:

- **User and problem:** who is affected and what outcome is blocked.
- **Evidence:** a reproducible report, user conversation, usability observation, support signal, or synthetic/public-domain acceptance fixture.
- **Status quo:** how the user handles this today and why it is inadequate.
- **Narrowest useful outcome:** the smallest end-to-end improvement that resolves the problem.
- **Acceptance criteria:** observable behavior, including failure and recovery paths.
- **Non-goals:** nearby work intentionally excluded.
- **Constraints and tradeoffs:** alternatives considered and why this choice wins now.
- **Impacts:** privacy, accessibility, durable data, performance, reliability, dependencies, documentation, and release notes.

Do not invent user research, demand, quotes, metrics, or confidence. Avail intentionally has no analytics; use qualitative evidence and reproducible behavior. Mark assumptions plainly and identify how they could be validated.

The user's explicit task may supply the product decision. Still state consequential assumptions and keep the implementation to the narrowest coherent scope. Do not turn a focused request into a redesign, speculative platform expansion, or unrelated cleanup.

### Changes that require an explicit product decision

Stop and obtain or record approval before changing any of these:

- The local-only/no-account/no-analytics/no-upload boundary or outgoing-network entitlement.
- Supported platforms or document formats, including OCR or DRM behavior.
- The 450-word progressive-playback threshold.
- Exact-position resume, stable identity, or playback continuity across routes and windows.
- Ownership, location, import, relocation, or deletion semantics for source books.
- The information sent to Now Playing or the wording of its privacy disclosure.
- The use of non-system narration providers.
- A core native macOS interaction described in `docs/ui-guidance.md`.

For a material product, architecture, privacy, or UX decision, update the relevant live document in the same change. Record context, decision, alternatives, consequences, and affected acceptance tests. If no live document fits, add a focused `docs/decisions/YYYY-MM-DD-<slug>.md`; do not create speculative planning archives.

## Repository map and boundaries

`Avail.xcodeproj` is the only build definition. Do not introduce a root `Package.swift` or use `swift build`/`swift test` as a substitute for the shared Xcode scheme.

- `Avail/App/`: SwiftUI application target. `AppEnvironment` is the `@MainActor` composition root.
- `Avail/App/Library/`: user-selected library location, imported source files, SwiftData records, artwork, and library behavior.
- `Avail/App/Indexing/`: orchestration and format selection; format parsing belongs in the format modules.
- `Avail/App/Playback/`: application-wide playback, persistence, and Now Playing coordination.
- `Avail/App/UI/`: library, persistent player, Zen, settings, and reusable presentation.
- `Modules/AvailCore/`: shared reading models, stable IDs, text chunking, indexing protocols, atomic storage, and rebuildable reading indexes.
- `Modules/AvailEPUB/`: EPUB package/content parsing and streaming indexing.
- `Modules/AvailPDF/`: PDFKit metadata/text extraction and streaming indexing.
- `Modules/AvailPlayback/`: narration models, `NarrationEngine`, and the system engine.
- `Tests/<Target>Tests/`: target-aligned XCTest suites plus `AvailUITests`.
- `Configuration/`: Info.plist and sandbox entitlements.
- `Scripts/` and `script/`: packaging/release verification and deterministic local build/run helpers.
- `Packaging/`: license material that must ship with public artifacts.

The primary import/index flow is:

`fileImporter -> AppEnvironment -> LibraryStore -> IndexingCoordinator -> EPUB/PDF indexer -> ReadingIndexStore`

Playback is a separate, user-triggered branch:

`Listen/Continue/chapter action -> PlaybackCoordinator -> LibraryStore + ReadingIndexStore -> SystemNarrationEngine -> Now Playing`

Respect these boundaries. Do not let SwiftUI views parse books, let format modules own app state, or couple coordinators directly to a concrete narration engine when a protocol exists.

The Xcode project uses file-system-synchronized target roots. File placement can determine target membership; add source and test files to the correct existing root and inspect the project diff carefully.

## Data, privacy, and security rules

Treat EPUBs, PDFs, their metadata, and filesystem paths as private and untrusted input.

- Never add production networking, analytics, telemetry, document uploads, cloud accounts, or remote speech to a core flow.
- Never log, paste into issues, or include in fixtures a user's book text, personal paths, bookmarks, or library metadata.
- Use synthetic or public-domain fixtures and redact private paths from diagnostics.
- Keep security-scoped resource access as short as practical: import or bookmark creation, not the lifetime of the app.
- Preserve App Sandbox, app-scoped security bookmarks, user-selected read/write access, hardened runtime, and the absence of outgoing-network entitlement.
- Do not place signing certificates, API keys, notarization credentials, or secret values in the repository, logs, commands shown to users, or fixtures.
- Validate malformed and adversarial document structures, cancellation, resource bounds, and partial failures. Parser work must not assume trusted archives or markup.

Classify data before changing storage behavior:

- **Durable user data:** source books in the chosen library, the library bookmark, SwiftData library records, reading position, voice/rate choices, and other user preferences.
- **Rebuildable derived data:** reading indexes under Application Support.
- **Source-derivable but not currently self-healing:** cached artwork. A missing or corrupt artwork file for a complete book currently becomes unavailable rather than being rebuilt automatically, so do not treat cache deletion as harmless without adding and testing a rebuild path.

Changes to import, relocation, schema, persistence, index recovery, or deletion must demonstrate idempotency, interruption recovery, and no loss of source books or reading progress. Route recoverable managed-file deletion through Trash and show confirmation before destructive user-facing actions.

## Swift and architecture expectations

- Use Swift 6 and preserve complete strict-concurrency correctness.
- Keep UI state, `AppEnvironment`, and UI-facing coordinators main-actor isolated.
- Keep file and indexing work off the main actor through the existing actors, utility tasks, and async stream boundaries.
- Preserve stable document/chapter/chunk identity and UTF-16 spoken-range semantics; playback persistence depends on both.
- Preserve progressive indexing, bounded batches, cancellation, atomic commits, corruption recovery, and buffering at the indexing frontier.
- Prefer focused types and existing service protocols. Add a dependency only after an explicit architecture/product decision.
- Xcode manages ZIPFoundation and SwiftSoup. Preserve `Package.resolved`, review dependency/license changes, and update `Packaging/THIRD_PARTY_NOTICES.md` when required.
- Add a focused failing test before changing behavior. A bug fix should contain a regression test that fails for the reported reason.
- Avoid unrelated formatting, renames, or refactors. Do not hide behavioral changes inside mechanical edits.

Do not edit generated or user/tool-owned paths as application source: `.build/`, `DerivedData/`, `dist/`, `xcuserdata/`, `.swiftpm/`, `.worktrees/`, `.superpowers/`, or `graphify-out/`. Preserve pre-existing worktree changes and never stage unrelated files.

## UI, accessibility, and recovery

Follow `docs/ui-guidance.md` and current official Apple Developer documentation/Human Interface Guidelines. Cite the relevant source in the decision record or pull request for a material UI choice.

- Prefer native SwiftUI navigation, window, toolbar, importer, menu, sheet, inspector, and settings behavior.
- Let native macOS surfaces provide glass; reserve custom glass for the coherent playback/action clusters already documented.
- Keep the persistent player visible on collection and detail routes. Only an explicit Listen, Continue, or chapter action may change narration.
- Keep Zen a standard resizable, value-keyed window. Closing it must not stop playback.
- Manual reading scroll suspends follow mode and exposes Return to Narration. Reduce Motion disables animated recentering.
- Never encode state by color alone. Spoken emphasis needs a semantic background plus a non-color cue.
- Errors need a specific title, plain-language cause, and one concrete recovery action.

For every user-visible UI change, verify and report:

- Keyboard access and standard shortcuts.
- VoiceOver labels, values, order, and actionable controls.
- Light and dark appearance.
- Increase Contrast, Reduce Transparency, and Reduce Motion where applicable.
- Full and compact persistent-player layouts.
- The separate Zen inspector and multi-window playback continuity.
- Empty, loading, partial-index, failure, and recovery states affected by the change.

Use [@Computer](plugin://computer-use@openai-bundled) for this manual/visual verification and attach screenshots or a concise observation record when useful. Automated snapshot or presentation tests do not replace accessibility interaction checks.

## Build and verification

Resolve dependencies when the lockfile/project changed or a clean build requires it:

```bash
xcodebuild -resolvePackageDependencies -project Avail.xcodeproj -scheme Avail
```

Run strict formatting for Swift changes:

```bash
swift format lint --strict --recursive --parallel \
  --configuration .swift-format Avail Modules Tests
```

Run the shared test action:

```bash
xcodebuild test \
  -project Avail.xcodeproj \
  -scheme Avail \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Use `-only-testing:<Target>/<Suite>` for a quick focused loop, but run the complete shared scheme before a pull request or after cross-module behavior changes.

Run the universal Release build before a pull request:

```bash
xcodebuild build \
  -project Avail.xcodeproj \
  -scheme Avail \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/ci \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO
```

For an unsigned local Release bundle, validate architecture, metadata, expected source entitlements, and absence of the outgoing-network entitlement:

```bash
ALLOW_UNSIGNED=1 EXPECTED_ARCHS='arm64 x86_64' \
  bash Scripts/verify-app.sh .build/ci/Build/Products/Release/Avail.app
```

`ALLOW_UNSIGNED=1` does not prove the built bundle's signature, hardened runtime, or embedded entitlements, and `verify-app.sh` does not inspect bundled license notices. For a public signed artifact, run the signed-bundle inspection in `docs/releasing.md` and verify that `LICENSE` and `Packaging/THIRD_PARTY_NOTICES.md` are present in the release deliverables.

`bash script/build_and_run.sh <build|test|archive|run|debug|logs|telemetry|verify>` is the deterministic local helper. Its launch modes terminate an already running Avail process; do not use them when that side effect is outside the task.

Apply verification proportionally:

- Documentation-only: inspect links/commands, run `git diff --check`, and verify claims against current sources.
- Domain/parser/playback change: formatter, focused target tests, and affected acceptance tests.
- Cross-module or persistence change: formatter, complete shared test scheme, recovery/data-integrity tests, and universal Release build.
- UI change: formatter, relevant unit/presentation/UI tests, a local build/run, and the manual accessibility matrix with `@Computer`.
- Packaging, entitlement, resource, app-startup, or release change: full gates plus `Scripts/verify-app.sh`.

Do not hard-code a historical test count. Report exact commands run and their result. If a required check cannot run, state the specific blocker and residual risk; never imply it passed.

## Pull requests, decisions, and releases

A change handoff or pull request should make review easy. Include:

- Linked issue or decision record when applicable.
- User-visible outcome and why this is the smallest appropriate change.
- Acceptance criteria and explicit non-goals.
- Important implementation choices and affected service boundaries.
- Privacy, accessibility, durable-data, schema/compatibility, and performance impact.
- Failure, recovery, rollback, and migration behavior.
- Exact automated and manual verification evidence.
- UI screenshots/recordings and accessibility configurations tested when applicable.
- Documentation and release-note impact.

Do not create tags, notarize, publish, upload artifacts, or make a GitHub release unless the user explicitly requests it. Releases must originate from a known-green `main` commit or rerun the full CI gates. Follow `docs/releasing.md`; ensure `vX.Y.Z` matches `MARKETING_VERSION`, build a universal Developer ID-signed hardened app, notarize, staple, verify, and publish checksums and licenses.

Do not infer an undocumented branch, commit-message, reviewer-count, or merge convention. Follow explicit maintainer direction and preserve the existing worktree.

## Definition of done

Before claiming completion:

- The requested user outcome and acceptance criteria are met.
- Product invariants and non-goals remain intact.
- Tests cover the changed behavior and meaningful failure/recovery paths.
- Relevant automated and manual checks have fresh evidence.
- Privacy, accessibility, data lifecycle, and documentation impacts were considered explicitly.
- The diff contains no unrelated files, generated artifacts, secrets, private content, or accidental project-setting changes.

Lead the final handoff with the outcome, then list changed files, verification performed, decisions/assumptions, and any remaining risk or follow-up. Never claim success from code inspection alone when an executable check is available.

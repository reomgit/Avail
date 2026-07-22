# Native Xcode and Liquid Glass Verification

Verified on 2026-07-16 from branch `codex/rebuild`.

## Build definition

- `Avail.xcodeproj` is the only Avail build definition.
- The shared `Avail` scheme contains the app, four static libraries, six unit-test bundles, and the UI-test bundle.
- The project is stored with Xcode 26-compatible object version 77 and Xcode 26 tool markers.
- ZIPFoundation 0.9.20 and SwiftSoup revision `83336847e47b2f499330c15426ad2fb180e72d9b` resolve through the Xcode workspace package lock.

The local machine has Xcode 27 beta, so local compilation used that newer toolchain. The CI and release jobs use the macOS 26 runner, and the project format matches projects created by Xcode 26.0 and 26.2 on this machine.

## Automated verification

```bash
xcodebuild -resolvePackageDependencies -project Avail.xcodeproj -scheme Avail
xcodebuild test -project Avail.xcodeproj -scheme Avail \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild clean build -project Avail.xcodeproj -scheme Avail \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/codex ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO
EXPECTED_ARCHS='arm64 x86_64' \
  bash Scripts/verify-app.sh .build/codex/Build/Products/Release/Avail.app
```

Results:

- 120 tests passed, with zero failures or skips.
- The strict recursive Swift format check passed.
- The clean universal Release build passed.
- Bundle identifier: `org.openavail.Avail`.
- Minimum system: macOS 26.0 in the bundle and both Mach-O slices.
- Architectures: `arm64` and `x86_64`.
- Signing: valid local signature with hardened runtime.
- Entitlements: App Sandbox, app-scoped bookmarks, and user-selected read/write access; no outgoing-network entitlement.
- EPUB and PDF document declarations and the Books application category are present.
- `LICENSE` and `Packaging/THIRD_PARTY_NOTICES.md` are copied into the app bundle.

## Computer verification

The current Debug app was exercised through Computer with the in-memory UI fixture:

- Music-style library grid, sidebar collections, search, and compact/full persistent-player compositions.
- Grid to Books-style detail to native Back navigation with the player remaining visible.
- Active narration remained on one book while browsing another.
- Selecting a chapter in another book's separate Zen window switched the shared session to that book and chapter.
- Closing Zen preserved playback and re-exposed the switched session in the main window player.
- The native Zen inspector toggle, chapter menu, transport, voice, speed, and progress controls remained available.
- The Preparing fixture remained in the Preparing collection during the session.

## Continuity and cleanup

Tests cover reopening the existing SwiftData schema without migration, resolving the existing `librarySecurityScopedBookmark` key, preserving the current Application Support layout, clearing an active session before removal, and deleting the removed book's derived reading index.

The final review reported no Critical or Important findings. `git diff --check`, project/plist/XML validation, shell syntax checks, and repository searches for a root `Package.swift`, linked-worktree paths, compatibility glass wrappers, and pre-macOS-26 availability branches all passed.

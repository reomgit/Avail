# Avail

Avail is an open-source, local-first EPUB and PDF listener for macOS. It indexes user-owned books on the Mac, narrates them with installed system voices, and provides an optional synchronized Zen reading view.

## Status

Avail is an MVP for macOS 26 or later with Swift 6.

## MVP Features

- Import EPUB and text-based PDF books into a folder you control.
- Start listening after the first 450 indexed words while the rest of the book prepares.
- Narrate with voices installed on the Mac; no cloud speech service is required.
- Resume at the exact spoken range after relaunch or a rebuilt derived index.
- Browse in a native Music-style library with an always-visible Liquid Glass player.
- Open Apple Books-style details without interrupting the current narration session.
- Read along in the separate Zen window with synchronized emphasis and a native playback inspector.
- Control playback from the keyboard, media keys, Control Center, and Now Playing.

## Principles

- Books and speech remain on the Mac.
- The library lives in a folder selected and controlled by the user.
- Apple Human Interface Guidelines and current SwiftUI documentation guide the UI.
- UI and Apple-framework decisions are checked against official documentation through Context7, with official Apple Developer documentation as the fallback.

Avail has no production networking or analytics client. During active playback only, book and playback metadata is provided to macOS Now Playing for system media controls.

## Build

Open `Avail.xcodeproj` in Xcode 26 or later and use the shared `Avail` scheme. The project is the only build definition; ZIPFoundation and SwiftSoup are managed by Xcode.

```bash
xcodebuild -resolvePackageDependencies -project Avail.xcodeproj -scheme Avail
xcodebuild test -project Avail.xcodeproj -scheme Avail -destination 'platform=macOS'
xcodebuild build -project Avail.xcodeproj -scheme Avail -configuration Release \
  -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

The app uses only Apple platform frameworks plus [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) and [SwiftSoup](https://github.com/scinfu/SwiftSoup), both under the MIT License.

For a deterministic local Debug build and launch:

```bash
bash script/build_and_run.sh run
```

Create a distributable bundle with Xcode’s Product > Archive command or `xcodebuild archive`. Public releases are universal, Developer ID signed, hardened, notarized, and stapled through the documented GitHub Actions workflow. See [Releasing Avail](docs/releasing.md) for credentials, commands, and artifact validation.

## MVP Limits

- PDFs must contain selectable text; OCR is not included yet.
- DRM-protected or encrypted EPUBs are rejected.
- The first narration provider uses voices installed by macOS through a pluggable local `NarrationEngine`; downloadable local neural-model providers are a post-MVP extension point.
- Avail currently targets macOS only.

Complete dependency notices are in [Third-Party Notices](Packaging/THIRD_PARTY_NOTICES.md) and are copied into every packaged app.

## License

Avail is available under the [MIT License](LICENSE).

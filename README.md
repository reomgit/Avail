# Avail

Avail is an open-source, local-first EPUB and PDF listener for macOS. It indexes user-owned books on the Mac, narrates them with installed system voices or user-supplied local voices, and provides an optional synchronized Zen reading view.

## Status

Avail is an MVP for macOS 26 or later with Swift 6.

## MVP Features

- Import EPUB and text-based PDF books into a folder you control.
- Start listening after the first 450 indexed words while the rest of the book prepares.
- Narrate with voices installed on the Mac; no cloud speech service is required.
- On Apple Silicon, link or copy a supported local neural voice model, or connect to a TTS server running on this Mac. System voices remain the default.
- A selected neural voice loads and prepares its first audio passage from the locally indexed book text before Play becomes available.
- Resume at the exact spoken range after relaunch or a rebuilt derived index.
- Browse in a native Music-style library with an always-visible Liquid Glass player.
- Open Apple Books-style details without interrupting the current narration session.
- Read along in the separate Zen window with synchronized emphasis and a native playback inspector.
- Control playback from the keyboard, media keys, Control Center, and Now Playing.

## Principles

- Books and speech remain on the Mac. A local TTS server receives passage text only when the user selects its voice.
- Generated neural phrases are cached locally to resume at the audible frame; older cache files are pruned when the cache grows beyond about 512 MiB.
- The library lives in a folder selected and controlled by the user.
- Apple Human Interface Guidelines and current SwiftUI documentation guide the UI.
- UI and Apple-framework decisions are checked against official documentation through Context7, with official Apple Developer documentation as the fallback.

Avail has no analytics, accounts, uploads, or remote speech service. The optional local-server voice uses a user-configured literal loopback address; the separate server receives the passage text sent for synthesis and controls its own storage, logging, and network behavior. Avail never sends that text to a remote TTS endpoint. During active playback only, book and playback metadata is provided to macOS Now Playing for system media controls.

## Build

Open `Avail.xcodeproj` in Xcode 26 or later and use the shared `Avail` scheme. The project is the only build definition; ZIPFoundation and SwiftSoup are managed by Xcode.

```bash
xcodebuild -resolvePackageDependencies -project Avail.xcodeproj -scheme Avail
xcodebuild test -project Avail.xcodeproj -scheme Avail -destination 'platform=macOS'
xcodebuild build -project Avail.xcodeproj -scheme Avail -configuration Release \
  -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

The app uses Apple platform frameworks plus the dependencies listed in [Third-Party Notices](Packaging/THIRD_PARTY_NOTICES.md). No voice model weights are bundled or downloaded by Avail.

For a deterministic local Debug build and launch:

```bash
bash script/build_and_run.sh run
```

Create a distributable bundle with Xcode’s Product > Archive command or `xcodebuild archive`. Public releases are universal, Developer ID signed, hardened, notarized, and stapled through the documented GitHub Actions workflow. See [Releasing Avail](docs/releasing.md) for credentials, commands, and artifact validation.

## MVP Limits

- PDFs must contain selectable text; OCR is not included yet.
- DRM-protected or encrypted EPUBs are rejected.
- Direct model import initially supports Fish Audio S2 Pro MLX folders. Other local TTS software can be connected through a compatible `/v1/audio/speech` loopback endpoint. Neural voices require Apple Silicon; Intel Macs retain system voices.
- Avail does not train, clone, convert, or download voice models. Users supply their own models and are responsible for their licenses. Built with Fish Audio support; the [Fish Audio agreement](Packaging/FISH_AUDIO_LICENSE.md) has separate commercial licensing terms.
- Avail currently targets macOS only.

Complete dependency notices are in [Third-Party Notices](Packaging/THIRD_PARTY_NOTICES.md) and are copied into every packaged app.

## License

Avail is available under the [MIT License](LICENSE).

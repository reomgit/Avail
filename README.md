# Avail

Avail is an open-source, local-first EPUB and PDF listener for macOS. It indexes user-owned books on the Mac, narrates them with installed system voices, and provides an optional synchronized Zen reading view.

## Status

Avail is an MVP for macOS 14 or later with Swift 6.

## MVP Features

- Import EPUB and text-based PDF books into a folder you control.
- Start listening after the first 450 indexed words while the rest of the book prepares.
- Narrate with voices installed on the Mac; no cloud speech service is required.
- Resume at the exact spoken range after relaunch or a rebuilt derived index.
- Read along in the Option B Zen window with synchronized emphasis and a persistent playback inspector.
- Control playback from the keyboard, media keys, Control Center, and Now Playing.

## Principles

- Books and speech remain on the Mac.
- The library lives in a folder selected and controlled by the user.
- Apple Human Interface Guidelines and current SwiftUI documentation guide the UI.
- UI and Apple-framework decisions are checked against official documentation through Context7, with official Apple Developer documentation as the fallback.

Avail has no production networking or analytics client. During active playback only, book and playback metadata is provided to macOS Now Playing for system media controls.

## Build

```bash
swift build
swift test
```

The app uses only Apple platform frameworks plus [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) and [SwiftSoup](https://github.com/scinfu/SwiftSoup), both under the MIT License.

## License

Avail is available under the [MIT License](LICENSE).

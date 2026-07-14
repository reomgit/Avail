# Avail

Avail is an open-source, local-first EPUB and PDF listener for macOS. It indexes user-owned books on the Mac, narrates them with installed system voices, and provides an optional synchronized Zen reading view.

## Status

Avail is in active MVP development. The current target is macOS 14 or later with Swift 6.

## Principles

- Books and speech remain on the Mac.
- The library lives in a folder selected and controlled by the user.
- Apple Human Interface Guidelines and current SwiftUI documentation guide the UI.
- UI and Apple-framework decisions are checked against official documentation through Context7, with official Apple Developer documentation as the fallback.

## Build

```bash
swift build
swift test
```

## License

Avail is available under the [MIT License](LICENSE).

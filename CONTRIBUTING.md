# Contributing to Avail

Thank you for helping make private, local book listening more accessible.

1. Open an issue before making a large product or architecture change.
2. Add a focused failing test before changing behavior.
3. Run the formatter check, the shared Xcode test action, and a Release build before opening a pull request.
4. Keep files focused and preserve the service boundaries in the design specification.
5. For UI work, cite the relevant Context7-backed Apple SwiftUI or Human Interface Guidelines source in the pull request and verify keyboard access, VoiceOver labels, light/dark appearance, and reduced-motion behavior.

Do not add analytics, document uploads, cloud accounts, or network requirements to core reading and narration flows.

```bash
swift format lint --strict --recursive --parallel --configuration .swift-format Avail Modules Tests
xcodebuild test -project Avail.xcodeproj -scheme Avail -destination 'platform=macOS'
xcodebuild build -project Avail.xcodeproj -scheme Avail -configuration Release \
  -destination 'platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

## Summary

Describe the user-visible outcome and why this is the smallest appropriate change.

## Verification

- [ ] `swift format lint --strict --recursive --parallel --configuration .swift-format Avail Modules Tests`
- [ ] `xcodebuild test -project Avail.xcodeproj -scheme Avail -destination 'platform=macOS'`
- [ ] Universal Release build through the shared `Avail` scheme
- [ ] `bash Scripts/verify-app.sh <path-to-Avail.app>` (when packaging, entitlements, resources, or app startup changes)

## Product and privacy

- [ ] Core book reading and narration still work without networking.
- [ ] No analytics, document upload, or outgoing-network entitlement was added.
- [ ] New failure modes have specific, actionable recovery.

## SwiftUI and accessibility

For UI changes, include the Context7-backed Apple documentation or Human Interface Guidelines sources used and verify:

- [ ] Keyboard access and VoiceOver labels
- [ ] Light and dark appearance
- [ ] Increase Contrast, Reduce Transparency, and Reduce Motion where applicable
- [ ] Full and compact persistent-player layouts plus the separate Zen inspector

## Summary

Describe the user-visible outcome and why this is the smallest appropriate change.

## Verification

- [ ] `swift format lint --strict --recursive --parallel --configuration .swift-format Sources Tests`
- [ ] `swift test --parallel`
- [ ] `swift build -c release`
- [ ] `bash Scripts/package-app.sh --clean && bash Scripts/verify-app.sh` (when packaging, entitlements, resources, or app startup changes)

## Product and privacy

- [ ] Core book reading and narration still work without networking.
- [ ] No analytics, document upload, or outgoing-network entitlement was added.
- [ ] New failure modes have specific, actionable recovery.

## SwiftUI and accessibility

For UI changes, include the Context7-backed Apple documentation or Human Interface Guidelines sources used and verify:

- [ ] Keyboard access and VoiceOver labels
- [ ] Light and dark appearance
- [ ] Increase Contrast, Reduce Transparency, and Reduce Motion where applicable
- [ ] The persistent Option B Zen listening layout at compact and expanded window sizes

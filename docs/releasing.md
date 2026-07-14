# Releasing Avail

Avail supports local ad hoc packages for contributors and Developer ID-signed, notarized universal packages for GitHub Releases. Ordinary debug builds do not require notarization.

Apple requires the hardened runtime for notarized software distributed outside the Mac App Store; App Sandbox is optional for that channel. Avail deliberately enables both. The only file capabilities are app-scoped security bookmarks and user-selected read/write access. The app has no outgoing-network entitlement. These decisions follow Apple’s [distribution preparation](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [App Sandbox entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox), and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) guidance, checked through Context7.

## Local package

Create and verify an ad hoc signed package:

```bash
bash Scripts/package-app.sh --clean
bash Scripts/verify-app.sh
open dist/Avail.app
```

Use `--arch arm64`, `--arch x86_64`, or `--arch universal` to select the executable architecture. An ad hoc package is intended for local validation; it is not a trusted public distribution.

## Developer ID package

Prerequisites:

- Apple Developer Program membership
- A `Developer ID Application` certificate in the active keychain
- App Store Connect API credentials with notarization access, or a notarytool keychain profile

Build, sign, submit, staple, and validate:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'
export VERSION='0.1.0'
export BUILD_NUMBER='1'
bash Scripts/package-app.sh --arch universal --clean

export APP_STORE_CONNECT_API_PRIVATE_KEY="$HOME/private_keys/AuthKey_KEYID.p8"
export APP_STORE_CONNECT_API_KEY_ID='KEYID'
export APP_STORE_CONNECT_API_ISSUER_ID='ISSUER-UUID'
bash Scripts/notarize.sh
bash Scripts/verify-app.sh
```

As an alternative to API-key environment variables, set `NOTARY_KEYCHAIN_PROFILE` to a profile previously created with `xcrun notarytool store-credentials`. Apple’s [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) documentation explains the trust and ticket model.

## GitHub release secrets

The tag-triggered workflow requires:

- `DEVELOPER_ID_APPLICATION`: exact signing identity name
- `DEVELOPER_ID_APPLICATION_P12_BASE64`: base64-encoded Developer ID certificate and private key
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: export password for that `.p12`
- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect key ID
- `APP_STORE_CONNECT_API_ISSUER_ID`: App Store Connect issuer UUID
- `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64`: base64-encoded `.p8` private key

Before pushing a `vX.Y.Z` tag, update `CFBundleShortVersionString` in `Packaging/Info.plist` to exactly `X.Y.Z`. The workflow imports the signing certificate into a temporary keychain, builds both architectures, creates a hardened and sandboxed universal app, notarizes and staples it, verifies Gatekeeper acceptance, and publishes the app, notices, and SHA-256 checksums.

Do not put signing or notarization credentials in the repository. Do not publish a tag until the release commit has passed CI and the verification checklist.

## Artifact inspection

The same checks used by CI are available locally:

```bash
plutil -p dist/Avail.app/Contents/Info.plist
codesign -dvvv --entitlements - --xml dist/Avail.app
codesign --verify --deep --strict --verbose=2 dist/Avail.app
xcrun stapler validate dist/Avail.app
spctl --assess --type execute --verbose=2 dist/Avail.app
```

For an ad hoc package, `codesign --verify` should pass while Gatekeeper assessment is expected to reject it. `spctl` acceptance is required only for the Developer ID-signed, notarized release artifact.

# Releasing Avail

Avail uses the shared `Avail` Xcode scheme for local builds, archives, tests, profiling, and releases. Ordinary Debug builds do not require notarization. Public downloads are universal Developer ID-signed archives with the hardened runtime, notarization ticket, and staple.

The application is sandboxed with app-scoped security bookmarks, user-selected read/write access, and a network-client entitlement for an opt-in, user-configured loopback TTS server. System and imported-model narration work without a server. The app must reject non-loopback addresses and redirects in code; the entitlement itself does not enforce that restriction.

## Local Xcode archive

In Xcode, open `Avail.xcodeproj`, choose the `Avail` scheme and **Any Mac**, then use **Product > Archive**. Organizer contains the resulting `.xcarchive` and can reveal or distribute the `.app`.

The equivalent command is:

```bash
xcodebuild archive \
  -project Avail.xcodeproj \
  -scheme Avail \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$PWD/dist/Avail.xcarchive" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO

EXPECTED_ARCHS='arm64 x86_64' \
  bash Scripts/verify-app.sh dist/Avail.xcarchive/Products/Applications/Avail.app
```

This is local archive validation. Gatekeeper acceptance is required only for the Developer ID-signed and notarized public artifact.

## Developer ID archive

Prerequisites:

- Apple Developer Program membership
- A `Developer ID Application` certificate in the active keychain
- App Store Connect API credentials with notarization access, or a `notarytool` keychain profile

Archive with the desired version and build number:

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Example (TEAMID)'

xcodebuild archive \
  -project Avail.xcodeproj \
  -scheme Avail \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$PWD/dist/Avail.xcarchive" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION='0.1.0' CURRENT_PROJECT_VERSION='1' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

ditto dist/Avail.xcarchive/Products/Applications/Avail.app dist/Avail.app
EXPECTED_ARCHS='arm64 x86_64' bash Scripts/verify-app.sh dist/Avail.app
```

Then configure one supported credential form and submit:

```bash
export APP_STORE_CONNECT_API_PRIVATE_KEY='/absolute/path/AuthKey_KEYID.p8'
export APP_STORE_CONNECT_API_KEY_ID='KEYID'
export APP_STORE_CONNECT_API_ISSUER_ID='ISSUER-UUID'
bash Scripts/notarize.sh dist/Avail.app
```

As an alternative, set `NOTARY_KEYCHAIN_PROFILE` to a profile created with `xcrun notarytool store-credentials`.

## GitHub release secrets

The tag-triggered workflow requires:

- `DEVELOPER_ID_APPLICATION`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64`

Before pushing a `vX.Y.Z` tag, set `MARKETING_VERSION` for the `Avail` target to `X.Y.Z`. The workflow imports the signing identity into a temporary keychain, creates an Xcode archive with both architectures, notarizes and staples the app, verifies it, and publishes the app, notices, the full Fish Audio agreement, Apache License 2.0 text, and SHA-256 checksums. Review the resolved Swift package graph and add license and notice text for every newly bundled dependency before releasing.

Do not store signing or notarization credentials in the repository.

## Artifact inspection

```bash
plutil -p dist/Avail.app/Contents/Info.plist
codesign -dvvv --entitlements :- dist/Avail.app
codesign --verify --deep --strict --verbose=2 dist/Avail.app
xcrun stapler validate dist/Avail.app
spctl --assess --type execute --verbose=2 dist/Avail.app
```

Inspect the signed Apple Silicon neural helper separately with `codesign -dvvv --entitlements :-` and `lipo -archs`, and verify it is embedded in the app before notarization. Verify that `LICENSE`, `Packaging/THIRD_PARTY_NOTICES.md`, `Packaging/FISH_AUDIO_LICENSE.md`, and `Packaging/APACHE-2.0_LICENSE.txt` ship with the app and the release licenses archive. Compare every pin in `Avail.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` to the notices before a public release.

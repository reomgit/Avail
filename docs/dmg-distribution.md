# DMG distribution

Public tagged releases include a compressed, universal `Avail-<version>-universal.dmg` alongside the ZIP archive, license bundle, and SHA-256 checksums. The DMG contains the signed and notarized `Avail.app` and an `Applications` shortcut for drag-and-drop installation.

The release workflow creates the DMG only after the app has been signed, notarized, stapled, and verified. It is triggered by pushing a `vX.Y.Z` tag whose version matches the Xcode `MARKETING_VERSION`. The same Developer ID certificate and App Store Connect notarization secrets described in [Releasing Avail](releasing.md#github-release-secrets) are required.

To install, open the DMG and drag `Avail.app` onto `Applications`. To check the downloaded image, compare its SHA-256 digest with the matching entry in `SHA256SUMS.txt` before opening it.

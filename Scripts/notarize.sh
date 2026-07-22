#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/dist/Avail.app}"
ARCHIVE_PATH="${ROOT_DIR}/dist/Avail-notarization.zip"

[[ -d "${APP_PATH}" ]] || { printf 'error: app bundle not found at %s\n' "${APP_PATH}" >&2; exit 1; }

SIGNING_DETAILS="$(codesign -dvv "${APP_PATH}" 2>&1)"
grep -q 'Authority=Developer ID Application' <<<"${SIGNING_DETAILS}" || {
    printf 'error: notarization requires a Developer ID Application signature\n' >&2
    exit 1
}

NOTARY_ARGUMENTS=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGUMENTS+=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE}")
elif [[ -n "${APP_STORE_CONNECT_API_PRIVATE_KEY:-}" && -n "${APP_STORE_CONNECT_API_KEY_ID:-}" && -n "${APP_STORE_CONNECT_API_ISSUER_ID:-}" ]]; then
    NOTARY_ARGUMENTS+=(
        --key "${APP_STORE_CONNECT_API_PRIVATE_KEY}"
        --key-id "${APP_STORE_CONNECT_API_KEY_ID}"
        --issuer "${APP_STORE_CONNECT_API_ISSUER_ID}"
    )
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" && -n "${TEAM_ID:-}" ]]; then
    NOTARY_ARGUMENTS+=(
        --apple-id "${APPLE_ID}"
        --password "${APP_SPECIFIC_PASSWORD}"
        --team-id "${TEAM_ID}"
    )
else
    printf 'error: configure a notary keychain profile, App Store Connect API key, or Apple ID credentials\n' >&2
    exit 1
fi

rm -f "${ARCHIVE_PATH}"
ditto -c -k --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"
xcrun notarytool submit "${ARCHIVE_PATH}" --wait "${NOTARY_ARGUMENTS[@]}"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"

printf 'Notarized and stapled %s\n' "${APP_PATH}"

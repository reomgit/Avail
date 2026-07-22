#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/.build/codex/Build/Products/Release/Avail.app}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
EXECUTABLE="${APP_PATH}/Contents/MacOS/Avail"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

[[ -d "${APP_PATH}" ]] || fail "app bundle not found at ${APP_PATH}"
[[ -f "${INFO_PLIST}" ]] || fail "Info.plist is missing"
[[ -x "${EXECUTABLE}" ]] || fail "Contents/MacOS/Avail is missing or not executable"

plutil -lint "${INFO_PLIST}" >/dev/null

BUNDLE_ID="$(${PLIST_BUDDY} -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
MINIMUM_SYSTEM="$(${PLIST_BUDDY} -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"
DOCUMENT_TYPES="$(${PLIST_BUDDY} -c 'Print :CFBundleDocumentTypes' "${INFO_PLIST}")"
DECLARED_EXECUTABLE="$(${PLIST_BUDDY} -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
CATEGORY="$(${PLIST_BUDDY} -c 'Print :LSApplicationCategoryType' "${INFO_PLIST}")"

[[ "${BUNDLE_ID}" == "org.openavail.Avail" ]] || fail "unexpected bundle identifier: ${BUNDLE_ID}"
[[ "${MINIMUM_SYSTEM}" == "26.0" ]] || fail "unexpected minimum macOS version: ${MINIMUM_SYSTEM}"
[[ "${DECLARED_EXECUTABLE}" == "Avail" ]] || fail "unexpected declared executable: ${DECLARED_EXECUTABLE}"
[[ "${CATEGORY}" == "public.app-category.books" ]] || fail "unexpected application category: ${CATEGORY}"
grep -q 'org.idpf.epub-container' <<<"${DOCUMENT_TYPES}" || fail "EPUB document type is missing"
grep -q 'com.adobe.pdf' <<<"${DOCUMENT_TYPES}" || fail "PDF document type is missing"

while read -r binary_minimum; do
    [[ "${binary_minimum}" == "26.0" ]] || fail "binary slice has unexpected minimum macOS version: ${binary_minimum}"
done < <(xcrun vtool -show-build "${EXECUTABLE}" | awk '/minos/ { print $2 }')

if [[ -n "${EXPECTED_ARCHS:-}" ]]; then
    for architecture in ${EXPECTED_ARCHS}; do
        lipo -verify_arch "${architecture}" "${EXECUTABLE}" \
            || fail "missing ${architecture} executable slice"
    done
fi

ENTITLEMENTS_FILE="$(mktemp -t avail-entitlements).plist"
trap 'rm -f "${ENTITLEMENTS_FILE}"' EXIT
SIGNING_STATE="signed"

if codesign --verify --deep --strict --verbose=2 "${APP_PATH}" >/dev/null 2>&1; then
    SIGNING_DETAILS="$(codesign -dvv "${APP_PATH}" 2>&1)"
    grep -q 'flags=.*runtime' <<<"${SIGNING_DETAILS}" || fail "hardened runtime is not enabled"
    codesign -d --entitlements :- "${APP_PATH}" >"${ENTITLEMENTS_FILE}" 2>/dev/null
else
    [[ "${ALLOW_UNSIGNED:-0}" == "1" ]] || fail "app bundle does not have a valid signature"
    SIGNING_STATE="unsigned metadata-only validation"
    cp "${ROOT_DIR}/Configuration/Avail.entitlements" "${ENTITLEMENTS_FILE}"
fi

plutil -lint "${ENTITLEMENTS_FILE}" >/dev/null

SANDBOX="$(${PLIST_BUDDY} -c 'Print :com.apple.security.app-sandbox' "${ENTITLEMENTS_FILE}")"
USER_FILES="$(${PLIST_BUDDY} -c 'Print :com.apple.security.files.user-selected.read-write' "${ENTITLEMENTS_FILE}")"
BOOKMARKS="$(${PLIST_BUDDY} -c 'Print :com.apple.security.files.bookmarks.app-scope' "${ENTITLEMENTS_FILE}")"

[[ "${SANDBOX}" == "true" ]] || fail "App Sandbox entitlement is not enabled"
[[ "${USER_FILES}" == "true" ]] || fail "user-selected read/write entitlement is not enabled"
[[ "${BOOKMARKS}" == "true" ]] || fail "app-scoped bookmark entitlement is not enabled"

if ${PLIST_BUDDY} -c 'Print :com.apple.security.network.client' "${ENTITLEMENTS_FILE}" >/dev/null 2>&1; then
    fail "outgoing network entitlement must not be present"
fi

printf 'Verified %s\n' "${APP_PATH}"
printf '  identifier: %s\n' "${BUNDLE_ID}"
printf '  minimum macOS: %s\n' "${MINIMUM_SYSTEM}"
printf '  architectures: %s\n' "$(lipo -archs "${EXECUTABLE}")"
printf '  signing: %s\n' "${SIGNING_STATE}"
printf '  sandboxed with app-scoped bookmarks and user-selected read/write access\n'

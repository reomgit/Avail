#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/.build/codex/Build/Products/Release/Avail.app}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
EXECUTABLE="${APP_PATH}/Contents/MacOS/Avail"
HELPER_PATH="${APP_PATH}/Contents/XPCServices/AvailNeuralHelper.xpc"
HELPER_INFO_PLIST="${HELPER_PATH}/Contents/Info.plist"
HELPER_EXECUTABLE="${HELPER_PATH}/Contents/MacOS/AvailNeuralHelper"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

[[ -d "${APP_PATH}" ]] || fail "app bundle not found at ${APP_PATH}"
[[ -f "${INFO_PLIST}" ]] || fail "Info.plist is missing"
[[ -x "${EXECUTABLE}" ]] || fail "Contents/MacOS/Avail is missing or not executable"
[[ -f "${APP_PATH}/Contents/Resources/LICENSE" ]] || fail "Avail license is missing from app resources"
[[ -f "${APP_PATH}/Contents/Resources/THIRD_PARTY_NOTICES.md" ]] \
    || fail "third-party notices are missing from app resources"
[[ -f "${APP_PATH}/Contents/Resources/FISH_AUDIO_LICENSE.md" ]] \
    || fail "Fish Audio agreement is missing from app resources"
[[ -f "${APP_PATH}/Contents/Resources/APACHE-2.0_LICENSE.txt" ]] \
    || fail "Apache 2.0 license is missing from app resources"
[[ -d "${HELPER_PATH}" ]] || fail "Apple Silicon neural helper is missing"
[[ -f "${HELPER_INFO_PLIST}" ]] || fail "neural helper Info.plist is missing"
[[ -x "${HELPER_EXECUTABLE}" ]] || fail "neural helper executable is missing or not executable"

plutil -lint "${INFO_PLIST}" >/dev/null
plutil -lint "${HELPER_INFO_PLIST}" >/dev/null

BUNDLE_ID="$(${PLIST_BUDDY} -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
MINIMUM_SYSTEM="$(${PLIST_BUDDY} -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"
DOCUMENT_TYPES="$(${PLIST_BUDDY} -c 'Print :CFBundleDocumentTypes' "${INFO_PLIST}")"
DECLARED_EXECUTABLE="$(${PLIST_BUDDY} -c 'Print :CFBundleExecutable' "${INFO_PLIST}")"
CATEGORY="$(${PLIST_BUDDY} -c 'Print :LSApplicationCategoryType' "${INFO_PLIST}")"
LOCAL_NETWORKING="$(${PLIST_BUDDY} -c 'Print :NSAppTransportSecurity:NSAllowsLocalNetworking' "${INFO_PLIST}")"
HELPER_BUNDLE_ID="$(${PLIST_BUDDY} -c 'Print :CFBundleIdentifier' "${HELPER_INFO_PLIST}")"
HELPER_DECLARED_EXECUTABLE="$(${PLIST_BUDDY} -c 'Print :CFBundleExecutable' "${HELPER_INFO_PLIST}")"

[[ "${BUNDLE_ID}" == "org.openavail.Avail" ]] || fail "unexpected bundle identifier: ${BUNDLE_ID}"
[[ "${MINIMUM_SYSTEM}" == "26.0" ]] || fail "unexpected minimum macOS version: ${MINIMUM_SYSTEM}"
[[ "${DECLARED_EXECUTABLE}" == "Avail" ]] || fail "unexpected declared executable: ${DECLARED_EXECUTABLE}"
[[ "${CATEGORY}" == "public.app-category.books" ]] || fail "unexpected application category: ${CATEGORY}"
[[ "${LOCAL_NETWORKING}" == "true" ]] || fail "ATS local networking exception is missing"
[[ "${HELPER_BUNDLE_ID}" == "org.openavail.Avail.NeuralHelper" ]] || fail "unexpected neural helper bundle identifier: ${HELPER_BUNDLE_ID}"
[[ "${HELPER_DECLARED_EXECUTABLE}" == "AvailNeuralHelper" ]] || fail "unexpected neural helper executable: ${HELPER_DECLARED_EXECUTABLE}"
grep -q 'org.idpf.epub-container' <<<"${DOCUMENT_TYPES}" || fail "EPUB document type is missing"
grep -q 'com.adobe.pdf' <<<"${DOCUMENT_TYPES}" || fail "PDF document type is missing"

while read -r binary_minimum; do
    [[ "${binary_minimum}" == "26.0" ]] || fail "binary slice has unexpected minimum macOS version: ${binary_minimum}"
done < <(xcrun vtool -show-build "${EXECUTABLE}" | awk '/minos/ { print $2 }')
while read -r binary_minimum; do
    [[ "${binary_minimum}" == "26.0" ]] || fail "neural helper slice has unexpected minimum macOS version: ${binary_minimum}"
done < <(xcrun vtool -show-build "${HELPER_EXECUTABLE}" | awk '/minos/ { print $2 }')
lipo -verify_arch arm64 "${HELPER_EXECUTABLE}" || fail "neural helper is missing its arm64 slice"

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
    codesign --verify --strict --verbose=2 "${HELPER_PATH}" >/dev/null 2>&1 \
        || fail "neural helper does not have a valid signature"
    HELPER_SIGNING_DETAILS="$(codesign -dvv "${HELPER_PATH}" 2>&1)"
    grep -q 'flags=.*runtime' <<<"${HELPER_SIGNING_DETAILS}" \
        || fail "neural helper hardened runtime is not enabled"
else
    [[ "${ALLOW_UNSIGNED:-0}" == "1" ]] || fail "app bundle does not have a valid signature"
    SIGNING_STATE="unsigned metadata-only validation"
    cp "${ROOT_DIR}/Configuration/Avail.entitlements" "${ENTITLEMENTS_FILE}"
fi

plutil -lint "${ENTITLEMENTS_FILE}" >/dev/null

SANDBOX="$(${PLIST_BUDDY} -c 'Print :com.apple.security.app-sandbox' "${ENTITLEMENTS_FILE}")"
USER_FILES="$(${PLIST_BUDDY} -c 'Print :com.apple.security.files.user-selected.read-write' "${ENTITLEMENTS_FILE}")"
BOOKMARKS="$(${PLIST_BUDDY} -c 'Print :com.apple.security.files.bookmarks.app-scope' "${ENTITLEMENTS_FILE}")"
NETWORK_CLIENT="$(${PLIST_BUDDY} -c 'Print :com.apple.security.network.client' "${ENTITLEMENTS_FILE}")"

[[ "${SANDBOX}" == "true" ]] || fail "App Sandbox entitlement is not enabled"
[[ "${USER_FILES}" == "true" ]] || fail "user-selected read/write entitlement is not enabled"
[[ "${BOOKMARKS}" == "true" ]] || fail "app-scoped bookmark entitlement is not enabled"
[[ "${NETWORK_CLIENT}" == "true" ]] || fail "network client entitlement is not enabled"

printf 'Verified %s\n' "${APP_PATH}"
printf '  identifier: %s\n' "${BUNDLE_ID}"
printf '  minimum macOS: %s\n' "${MINIMUM_SYSTEM}"
printf '  architectures: %s\n' "$(lipo -archs "${EXECUTABLE}")"
printf '  neural helper architectures: %s\n' "$(lipo -archs "${HELPER_EXECUTABLE}")"
printf '  signing: %s\n' "${SIGNING_STATE}"
printf '  sandboxed with app-scoped bookmarks, user-selected read/write, and network client access\n'

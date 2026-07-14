#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${ROOT_DIR}/dist/Avail.app"
ARCHITECTURE="$(uname -m)"
CLEAN=false

usage() {
    cat <<'EOF'
Usage: Scripts/package-app.sh [--arch arm64|x86_64|universal] [--clean]

Environment:
  DEVELOPER_ID_APPLICATION  Signing identity. Defaults to ad hoc signing.
  VERSION                   Overrides CFBundleShortVersionString.
  BUILD_NUMBER              Overrides CFBundleVersion.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            ARCHITECTURE="$2"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "${ARCHITECTURE}" in
    arm64|x86_64|universal) ;;
    *)
        printf 'error: unsupported architecture: %s\n' "${ARCHITECTURE}" >&2
        exit 2
        ;;
esac

if [[ "${CLEAN}" == true ]]; then
    rm -rf "${APP_PATH}"
fi

build_product() {
    local architecture="$1"
    local scratch_path="${2:-}"
    local arguments=(-c release --arch "${architecture}")
    if [[ -n "${scratch_path}" ]]; then
        arguments=(--scratch-path "${scratch_path}" "${arguments[@]}")
    fi

    swift build "${arguments[@]}"
    swift build "${arguments[@]}" --show-bin-path
}

cd "${ROOT_DIR}"

if [[ "${ARCHITECTURE}" == universal ]]; then
    ARM_BIN_PATH="$(build_product arm64 "${ROOT_DIR}/.build/universal-arm64" | tail -1)"
    INTEL_BIN_PATH="$(build_product x86_64 "${ROOT_DIR}/.build/universal-x86_64" | tail -1)"
    RESOURCE_BIN_PATH="${ARM_BIN_PATH}"
else
    BIN_PATH="$(build_product "${ARCHITECTURE}" | tail -1)"
    RESOURCE_BIN_PATH="${BIN_PATH}"
fi

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources/Licenses"
cp "${ROOT_DIR}/Packaging/Info.plist" "${APP_PATH}/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"
fi

if [[ "${ARCHITECTURE}" == universal ]]; then
    lipo -create "${ARM_BIN_PATH}/Avail" "${INTEL_BIN_PATH}/Avail" -output "${APP_PATH}/Contents/MacOS/Avail"
else
    cp "${BIN_PATH}/Avail" "${APP_PATH}/Contents/MacOS/Avail"
fi
chmod 755 "${APP_PATH}/Contents/MacOS/Avail"

shopt -s nullglob
RESOURCE_BUNDLES=("${RESOURCE_BIN_PATH}"/*.bundle)
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    cp -R "${bundle}" "${APP_PATH}/Contents/Resources/"
done
shopt -u nullglob

cp "${ROOT_DIR}/LICENSE" "${APP_PATH}/Contents/Resources/Licenses/Avail-LICENSE.txt"
cp "${ROOT_DIR}/Packaging/THIRD_PARTY_NOTICES.md" "${APP_PATH}/Contents/Resources/Licenses/"

xattr -cr "${APP_PATH}"

SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
SIGNING_ARGUMENTS=(
    --force
    --options runtime
    --entitlements "${ROOT_DIR}/Packaging/Avail.entitlements"
    --sign "${SIGNING_IDENTITY}"
)
if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    SIGNING_ARGUMENTS+=(--timestamp=none)
else
    SIGNING_ARGUMENTS+=(--timestamp)
fi

codesign "${SIGNING_ARGUMENTS[@]}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

printf 'Packaged %s (%s, identity: %s)\n' "${APP_PATH}" "$(lipo -archs "${APP_PATH}/Contents/MacOS/Avail")" "${SIGNING_IDENTITY}"

#!/bin/bash

set -euo pipefail

MODE="${1:-run}"
APP_NAME="Avail"
BUNDLE_ID="org.openavail.Avail"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${AVAIL_DERIVED_DATA:-${ROOT_DIR}/.build/codex}"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Debug/Avail.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/Avail"
ARCHIVE_PATH="${ROOT_DIR}/dist/Avail.xcarchive"

build_app() {
    xcodebuild build \
        -project "${ROOT_DIR}/Avail.xcodeproj" \
        -scheme Avail \
        -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "${DERIVED_DATA}"
}

open_app() {
    /usr/bin/open -n "${APP_BUNDLE}"
}

case "${MODE}" in
    build)
        build_app
        ;;
    test)
        xcodebuild test \
            -project "${ROOT_DIR}/Avail.xcodeproj" \
            -scheme Avail \
            -destination 'platform=macOS' \
            -derivedDataPath "${DERIVED_DATA}"
        ;;
    archive)
        mkdir -p "${ROOT_DIR}/dist"
        xcodebuild archive \
            -project "${ROOT_DIR}/Avail.xcodeproj" \
            -scheme Avail \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -archivePath "${ARCHIVE_PATH}" \
            ARCHS='arm64 x86_64' \
            ONLY_ACTIVE_ARCH=NO
        ;;
    run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
        pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
        build_app

        case "${MODE}" in
            run)
                open_app
                ;;
            --debug|debug)
                lldb -- "${APP_BINARY}"
                ;;
            --logs|logs)
                open_app
                /usr/bin/log stream --info --style compact --predicate "process == \"${APP_NAME}\""
                ;;
            --telemetry|telemetry)
                open_app
                /usr/bin/log stream --info --style compact --predicate "subsystem == \"${BUNDLE_ID}\""
                ;;
            --verify|verify)
                open_app
                for _ in {1..10}; do
                    if pgrep -x "${APP_NAME}" >/dev/null; then
                        printf '%s launched successfully from %s\n' "${APP_NAME}" "${APP_BUNDLE}"
                        exit 0
                    fi
                    sleep 0.5
                done
                printf 'error: %s did not stay running\n' "${APP_NAME}" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        printf 'usage: %s [build|test|archive|run|debug|logs|telemetry|verify]\n' "$0" >&2
        exit 2
        ;;
esac

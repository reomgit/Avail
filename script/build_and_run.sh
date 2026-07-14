#!/bin/bash

set -euo pipefail

MODE="${1:-run}"
APP_NAME="Avail"
BUNDLE_ID="org.openavail.Avail"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/dist/Avail.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/Avail"

pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
bash "${ROOT_DIR}/Scripts/package-app.sh"

open_app() {
    /usr/bin/open -n "${APP_BUNDLE}"
}

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
    *)
        printf 'usage: %s [run|--debug|--logs|--telemetry|--verify]\n' "$0" >&2
        exit 2
        ;;
esac

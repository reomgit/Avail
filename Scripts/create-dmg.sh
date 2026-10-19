#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <app-path> <version> <output-dmg>" >&2
  exit 2
fi

APP_PATH="$1"
VERSION="$2"
OUTPUT_DMG="$3"

if [[ ! -d "${APP_PATH}" || "${APP_PATH##*.}" != "app" ]]; then
  echo "Expected an existing .app bundle: ${APP_PATH}" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "${OUTPUT_DMG}")"
mkdir -p "${OUTPUT_DIR}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/avail-dmg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

ditto "${APP_PATH}" "${STAGING_DIR}/Avail.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "Avail ${VERSION}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${OUTPUT_DMG}"
hdiutil verify "${OUTPUT_DMG}"

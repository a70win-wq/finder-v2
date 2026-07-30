#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="${PROJECT_DIR}/build"
DIST_DIR="${PROJECT_DIR}/dist"
APP_PATH="${BUILD_DIR}/Finder v2.0.app"
DMG_NAME="Finder-v2.0-macOS.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/FinderV2-DMG.XXXXXX")"

cleanup() {
    if [[ -n "${DMG_STAGE:-}" && "${DMG_STAGE}" == *"/FinderV2-DMG."* ]]; then
        rm -rf "${DMG_STAGE}"
    fi
}
trap cleanup EXIT

"${SCRIPT_DIR}/build-app.sh"

mkdir -p "${DIST_DIR}"
ditto "${APP_PATH}" "${DMG_STAGE}/Finder v2.0.app"
ln -s /Applications "${DMG_STAGE}/Applications"
ditto "${PROJECT_DIR}/Resources/DMG-README.txt" "${DMG_STAGE}/安裝方法.txt"

/usr/bin/hdiutil create \
    -volname "Finder v2.0" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

/usr/bin/codesign --force --sign - "${DMG_PATH}"
(
    cd "${DIST_DIR}"
    /usr/bin/shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
)

print "${DMG_PATH}"

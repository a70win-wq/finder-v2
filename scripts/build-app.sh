#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="${BUILD_DIR}/Finder v2.0.app"
CONTENTS_PATH="${APP_PATH}/Contents"
MACOS_PATH="${CONTENTS_PATH}/MacOS"
RESOURCES_PATH="${CONTENTS_PATH}/Resources"
ARM64_BIN_PATH="${BUILD_DIR}/FinderV2-arm64"
X86_64_BIN_PATH="${BUILD_DIR}/FinderV2-x86_64"
UNIVERSAL_BIN_PATH="${BUILD_DIR}/FinderV2-universal"
SOURCE_FILES=("${PROJECT_DIR}"/Sources/FinderV2/*.swift)

mkdir -p "${BUILD_DIR}"
/usr/bin/xcrun swiftc \
    -O \
    -parse-as-library \
    -target arm64-apple-macosx14.0 \
    "${SOURCE_FILES[@]}" \
    -o "${ARM64_BIN_PATH}"

/usr/bin/xcrun swiftc \
    -O \
    -parse-as-library \
    -target x86_64-apple-macosx14.0 \
    "${SOURCE_FILES[@]}" \
    -o "${X86_64_BIN_PATH}"

/usr/bin/lipo \
    -create \
    "${ARM64_BIN_PATH}" \
    "${X86_64_BIN_PATH}" \
    -output "${UNIVERSAL_BIN_PATH}"

if [[ -e "${APP_PATH}" ]]; then
    rm -rf "${APP_PATH}"
fi

mkdir -p "${MACOS_PATH}" "${RESOURCES_PATH}"
ditto "${UNIVERSAL_BIN_PATH}" "${MACOS_PATH}/FinderV2"
ditto "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_PATH}/Info.plist"
ditto "${PROJECT_DIR}/Resources/AppIcon.icns" "${RESOURCES_PATH}/AppIcon.icns"
chmod 755 "${MACOS_PATH}/FinderV2"
codesign --force --deep --sign - "${APP_PATH}"

print "${APP_PATH}"

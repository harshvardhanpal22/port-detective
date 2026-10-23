#!/usr/bin/env bash
# Builds "Port Detective.app" from the Swift package.
#
#   ./build.sh             build into ./build
#   ./build.sh run         build and launch
#   ./build.sh install     build, copy to /Applications and launch
#   UNIVERSAL=1 ./build.sh build one app that runs on both Apple silicon and Intel
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Port Detective"
EXECUTABLE="PortDetective"
APP_DIR="build/${APP_NAME}.app"

ARCH_ARGS=""
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_ARGS="--arch arm64 --arch x86_64"
fi

echo "Compiling…"
# shellcheck disable=SC2086  # ARCH_ARGS is intentionally split into words
swift build -c release $ARCH_ARGS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c release $ARCH_ARGS --show-bin-path)"

echo "Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${EXECUTABLE}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

if [[ -d Resources/AppIcon.iconset ]] && command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns Resources/AppIcon.iconset -o "${APP_DIR}/Contents/Resources/AppIcon.icns" \
    || echo "Couldn't build the icon; continuing without it."
fi

# Downloaded source files carry a quarantine flag, and codesign refuses
# bundles with extended attributes, so clear them before signing.
xattr -cr "${APP_DIR}" 2>/dev/null || true

echo "Signing (ad-hoc, for running on this Mac)"
codesign --force --sign - "${APP_DIR}"

case "${1:-}" in
  run)
    pkill -x "${EXECUTABLE}" 2>/dev/null || true
    open "${APP_DIR}"
    echo "Running. Look for the connector icon in your menu bar."
    ;;
  install)
    pkill -x "${EXECUTABLE}" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    ditto "${APP_DIR}" "/Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
    echo "Installed to /Applications/${APP_NAME}.app"
    ;;
  *)
    echo "Built ${APP_DIR}"
    ;;
esac

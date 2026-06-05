#!/bin/bash
# Fast local install for development: build the app bundle (native arch only,
# ad-hoc signed, no DMG/notarization) and replace /Applications/Mac Sai.app
# with it. For checking a branch build on your own machine in about a minute;
# real releases still go through build-dmg.sh --notarize in CI.
#
# Usage: ./scripts/dev-install.sh

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mac Sai"
APP_BUNDLE=".build/dmg/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

echo "=== Dev install: building ${APP_NAME} ($(uname -m) only, ad-hoc signed) ==="
BUILD_ARCHS="--arch $(uname -m)" ./scripts/build-dmg.sh --app-only

# Quit the running app and its menu bar helper before swapping the bundle.
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x MacCleanMenu 2>/dev/null || true
pkill -x MacClean 2>/dev/null || true
sleep 1

echo "Installing to ${DEST}..."
rm -rf "${DEST}"
ditto "${APP_BUNDLE}" "${DEST}"

echo "Launching..."
open "${DEST}"

echo ""
echo "Done. Notes:"
echo "  - This build is ad-hoc signed; its signature differs from the notarized"
echo "    release, so macOS may ask you to re-grant Full Disk Access"
echo "    (System Settings -> Privacy & Security -> Full Disk Access)."
echo "  - A later 'brew upgrade --cask mac-sai' will overwrite this dev build."

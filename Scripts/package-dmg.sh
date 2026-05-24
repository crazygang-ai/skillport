#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/package-dmg.sh <app-path> <version> [output-dir]
# Example: ./Scripts/package-dmg.sh build/export/Skillport.app 0.1.0 build/export

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "Usage: $0 <app-path> <version> [output-dir]"
    exit 2
fi

APP_PATH="$1"
VERSION="$2"
OUTPUT_DIR="${3:-$(dirname "$APP_PATH")}"

if [ ! -d "$APP_PATH" ]; then
    echo "App bundle not found: $APP_PATH"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

DMG_PATH="$OUTPUT_DIR/Skillport-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skillport-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/Skillport.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "Skillport" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "DMG ready: $DMG_PATH"

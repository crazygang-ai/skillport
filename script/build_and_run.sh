#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Skillport"
BUNDLE_ID="ai.crazygang.Skillport"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

build_app() {
    xcodebuild \
        -scheme "$APP_NAME" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination 'platform=macOS,arch=arm64' \
        CODE_SIGNING_ALLOWED=NO \
        build \
        -quiet
}

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
build_app

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 2
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        usage
        exit 2
        ;;
esac

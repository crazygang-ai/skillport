#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
if [ -f Package.resolved ]; then
    RESOLVED_DIR="Skillport.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
    mkdir -p "$RESOLVED_DIR"
    cp Package.resolved "$RESOLVED_DIR/Package.resolved"
fi
echo "Generated Skillport.xcodeproj"

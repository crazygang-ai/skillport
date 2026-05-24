#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/release.sh <version>
# Example: ./Scripts/release.sh 0.1.0
# Produces an ad-hoc signed DMG for GitHub Release download.

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.1.0"
    exit 2
fi

VERSION="$1"
BUILD="$(date +%Y%m%d%H%M)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Releasing Skillport v$VERSION build $BUILD"

PROJECT_VERSION_COMMITTED=false
restore_project_version() {
    if [ "$PROJECT_VERSION_COMMITTED" = false ]; then
        git checkout -- project.yml Skillport.xcodeproj/project.pbxproj >/dev/null 2>&1 || true
    fi
}
trap restore_project_version ERR

# 1. Check clean working tree
if ! git diff-index --quiet HEAD --; then
    echo "Working tree not clean; commit or stash first"
    exit 1
fi

# 2. Bump version in project.yml
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml

./Scripts/generate-project.sh

# 3. Pre-flight: tests + lint + parity
./Scripts/check-parser-parity.sh
swift-format lint --recursive App Domain Tests SkillportPreview

run_tests() {
    if command -v xcpretty >/dev/null 2>&1; then
        xcodebuild -scheme Skillport -destination 'platform=macOS' test | xcpretty
    else
        echo "==> xcpretty not found; running raw xcodebuild test output"
        xcodebuild -scheme Skillport -destination 'platform=macOS' test
    fi
}

run_tests

# 4. Build release app with ad-hoc signing
DERIVED_DATA="$REPO_ROOT/build/release-derived-data-$VERSION"
EXPORT_DIR="$REPO_ROOT/build/export-$VERSION"
rm -rf "$DERIVED_DATA" "$EXPORT_DIR"

xcodebuild \
    -scheme Skillport \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    build

# 5. Stage .app and package DMG
mkdir -p "$EXPORT_DIR"
ditto "$DERIVED_DATA/Build/Products/Release/Skillport.app" "$EXPORT_DIR/Skillport.app"
./Scripts/package-dmg.sh "$EXPORT_DIR/Skillport.app" "$VERSION" "$EXPORT_DIR"

# 6. Commit + tag
git add project.yml Skillport.xcodeproj/project.pbxproj
git commit -m "chore(release): bump to v$VERSION build $BUILD"
git tag "v$VERSION"
PROJECT_VERSION_COMMITTED=true
trap - ERR

echo ""
echo "Release v$VERSION built to $EXPORT_DIR/Skillport-$VERSION.dmg"
echo ""
echo "Next steps:"
echo "  1. Push: git push && git push --tags"
echo "  2. Download DMG from the GitHub Release created by CI"

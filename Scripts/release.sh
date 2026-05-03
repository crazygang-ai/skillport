#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/release.sh <version>
# Example: ./Scripts/release.sh 0.1.0
# Requires: Developer ID 证书装在 Keychain (见 docs/RELEASE-SETUP.md)。

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

# 1. 检查 clean working tree
if ! git diff-index --quiet HEAD --; then
    echo "❌ Working tree not clean; commit or stash first"
    exit 1
fi

# 2. Bump version in project.yml
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: .*/MARKETING_VERSION: \"$VERSION\"/" project.yml
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION: .*/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml

./Scripts/generate-project.sh

# 3. Pre-flight: tests + lint + parity
./Scripts/check-parser-parity.sh
swift-format lint --recursive App Domain Tests SkillportPreview
xcodebuild -scheme Skillport -destination 'platform=macOS' test | xcpretty || {
    echo "❌ Tests failed; aborting release"
    git checkout project.yml
    exit 1
}

# 4. Archive
ARCHIVE_PATH="$REPO_ROOT/build/Skillport-$VERSION.xcarchive"
xcodebuild archive \
    -scheme Skillport \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release

# 5. Export .app
EXPORT_DIR="$REPO_ROOT/build/export-$VERSION"
mkdir -p "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist build/ExportOptions.plist

# 6. Commit + tag
git add project.yml
git commit -m "chore(release): bump to v$VERSION build $BUILD"
git tag "v$VERSION"

echo ""
echo "✅ Release v$VERSION built to $EXPORT_DIR/Skillport.app"
echo ""
echo "Next steps:"
echo "  1. Notarize:       ./Scripts/notarize.sh \"$EXPORT_DIR/Skillport.app\""
echo "  2. Publish appcast: ./Scripts/publish-appcast.sh \"$EXPORT_DIR\" $VERSION"
echo "  3. Push:           git push && git push --tags"

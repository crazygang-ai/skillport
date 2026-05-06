#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/publish-appcast.sh <export-dir> <version>
# Example: ./Scripts/publish-appcast.sh build/export-0.1.0 0.1.0
#
# Requires env vars:
#   SPARKLE_PRIVATE_KEY_PATH  - path to EdDSA private key file
#   APPCAST_DMG_BASE_URL      - e.g. https://updates.example.com or GH Release URL prefix
#   SPARKLE_SIGN_UPDATE       - (optional) path to sign_update binary if not on PATH
#   APPCAST_URL               - (optional) URL of the appcast.xml itself

EXPORT_DIR="${1:?usage: publish-appcast.sh <export-dir> <version>}"
VERSION="${2:?need version}"
APP_PATH="$EXPORT_DIR/Skillport.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ $APP_PATH does not exist; run release.sh first"
    exit 1
fi

# 1. Package into .dmg
DMG_PATH="$EXPORT_DIR/Skillport-$VERSION.dmg"
echo "==> Creating $DMG_PATH..."
rm -f "$DMG_PATH"
hdiutil create -volname "Skillport" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

# 2. Find sign_update tool
SIGN_TOOL="${SPARKLE_SIGN_UPDATE:-}"
if [ -z "$SIGN_TOOL" ]; then
    # Try Xcode-bundled or Sparkle SPM build
    DERIVED_SIGN_UPDATE="$HOME"/Library/Developer/Xcode/DerivedData/Skillport-*/SourcePackages/artifacts/Sparkle/bin/sign_update
    for candidate in \
        "$(xcrun --find sign_update 2>/dev/null || echo '')" \
        "./SourcePackages/artifacts/Sparkle/bin/sign_update" \
        $DERIVED_SIGN_UPDATE; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            SIGN_TOOL="$candidate"
            break
        fi
    done
fi
if [ -z "$SIGN_TOOL" ] || [ ! -x "$SIGN_TOOL" ]; then
    echo "❌ sign_update tool not found"
    echo "   Either set SPARKLE_SIGN_UPDATE, or install Sparkle 2 and let xcodebuild resolve it."
    exit 1
fi

# 3. Sign DMG with EdDSA
KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:?set SPARKLE_PRIVATE_KEY_PATH}"
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ SPARKLE_PRIVATE_KEY_PATH file not found: $KEY_PATH"
    exit 1
fi
echo "==> Signing $DMG_PATH with EdDSA..."
SIGNATURE=$("$SIGN_TOOL" -f "$KEY_PATH" "$DMG_PATH")
LENGTH=$(stat -f%z "$DMG_PATH")

# 4. Generate appcast from template
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/build/appcast.template.xml"
if [ ! -f "$TEMPLATE" ]; then
    echo "❌ Appcast template not found at $TEMPLATE"
    exit 1
fi
APPCAST_PATH="$EXPORT_DIR/appcast.xml"
cp "$TEMPLATE" "$APPCAST_PATH"

BASE_URL="${APPCAST_DMG_BASE_URL:?set APPCAST_DMG_BASE_URL}"
BASE_URL="${BASE_URL%/}"
DMG_URL="$BASE_URL/Skillport-$VERSION.dmg"
APPCAST_FEED_URL="${APPCAST_URL:-$BASE_URL/appcast.xml}"

/usr/bin/sed -i '' "s|{{VERSION}}|$VERSION|g" "$APPCAST_PATH"
/usr/bin/sed -i '' "s|{{PUBDATE}}|$(date -R)|g" "$APPCAST_PATH"
/usr/bin/sed -i '' "s|{{LENGTH}}|$LENGTH|g" "$APPCAST_PATH"
/usr/bin/sed -i '' "s|{{SIGNATURE}}|$SIGNATURE|g" "$APPCAST_PATH"
/usr/bin/sed -i '' "s|{{DMG_URL}}|$DMG_URL|g" "$APPCAST_PATH"
/usr/bin/sed -i '' "s|{{APPCAST_URL}}|$APPCAST_FEED_URL|g" "$APPCAST_PATH"

echo ""
echo "✅ Appcast generated: $APPCAST_PATH"
echo "✅ DMG ready:         $DMG_PATH"
echo ""
echo "Next: upload both files to your hosting (GitHub Release / CDN / domain)."

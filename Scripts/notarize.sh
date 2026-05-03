#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/notarize.sh <path-to-Skillport.app>
#
# Requires one of:
#   (a) AC_PROFILE env var pointing to a Keychain profile created with:
#       xcrun notarytool store-credentials AC_PROFILE \
#         --apple-id you@example.com --team-id TEAMID \
#         --password APP_SPECIFIC_PASSWORD
#   (b) AC_USERNAME + AC_TEAM_ID + AC_APP_SPECIFIC_PASSWORD env vars.

APP_PATH="${1:?usage: notarize.sh <path-to-Skillport.app>}"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ $APP_PATH is not a directory"
    exit 1
fi

ZIP_PATH="${APP_PATH%.app}.zip"
echo "==> Packaging $APP_PATH → $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to notarytool..."
if [ -n "${AC_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$AC_PROFILE" \
        --wait
else
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "${AC_USERNAME:?set AC_USERNAME or AC_PROFILE}" \
        --team-id "${AC_TEAM_ID:?set AC_TEAM_ID}" \
        --password "${AC_APP_SPECIFIC_PASSWORD:?set AC_APP_SPECIFIC_PASSWORD}" \
        --wait
fi

echo "==> Stapling ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo ""
echo "✅ Notarization complete: $APP_PATH"

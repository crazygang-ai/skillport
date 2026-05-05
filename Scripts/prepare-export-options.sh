#!/usr/bin/env bash
set -euo pipefail

# Usage: ./Scripts/prepare-export-options.sh <output-plist>
# Replaces the ExportOptions.plist team placeholder with a real Apple Team ID.

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <output-plist>"
    exit 2
fi

OUT="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/build/ExportOptions.plist"

TEAM_ID="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM_ID" ]; then
    TEAM_ID="$(
        /usr/bin/awk -F '"' '
            /DEVELOPMENT_TEAM:/ {
                print $2
                exit
            }
        ' "$REPO_ROOT/project.yml"
    )"
fi

if ! [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "❌ DEVELOPMENT_TEAM must be a 10-character Apple Team ID"
    echo "   Set DEVELOPMENT_TEAM in the environment or project.yml before exporting."
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
TMP="$OUT.tmp"
/usr/bin/sed "s|\$(DEVELOPMENT_TEAM)|$TEAM_ID|g" "$TEMPLATE" > "$TMP"
mv "$TMP" "$OUT"

echo "Prepared export options: $OUT"

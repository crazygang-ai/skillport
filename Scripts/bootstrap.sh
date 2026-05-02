#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing xcodegen via Homebrew..."
    brew install xcodegen
fi

if ! command -v swift-format >/dev/null 2>&1; then
    echo "Installing swift-format via Homebrew..."
    brew install swift-format
fi

echo "Bootstrap complete."

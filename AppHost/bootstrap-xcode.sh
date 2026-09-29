#!/usr/bin/env bash
# Run on a Mac from the repo root after the core XCFrameworks exist (App/Vendor/*.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d App/Vendor/Output/mGBA.xcframework ]]; then
  echo "Missing App/Vendor/Output/mGBA.xcframework — run App/Vendor/build-mgba-ios.sh first." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null; then
  echo "Installing xcodegen via brew..."
  brew install xcodegen
fi

git pull --ff-only || true
xcodegen generate
open RetroPlay.xcodeproj
echo "Opened RetroPlay.xcodeproj — select an iOS Simulator and Run (⌘R)."

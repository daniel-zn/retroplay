#!/usr/bin/env bash
# Build melonDS (interpreter, no JIT) for iOS and pack an XCFramework into
# App/Vendor/Output/melonDS.xcframework (gitignored).
#
# Run on a Mac with Xcode + CMake. This script documents the intended layout;
# fill MELONDS_* paths after a successful upstream build.
# Do not run on the Linux Grok Bot box. Do not enable JIT.
set -euo pipefail

ROOT="${RETROPLAY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="$ROOT/App/Vendor/Output"
MELONDS_SRC="${MELONDS_SRC:-$HOME/src/melonDS}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-18.0}"

echo "RetroPlay melonDS XCFramework helper"
echo "  ROOT=$ROOT"
echo "  MELONDS_SRC=$MELONDS_SRC"
echo "  OUT=$OUT"
echo "  DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
echo
echo "Target config: interpreter only (no JIT)."
echo
echo "Build upstream for iphoneos (+ optional simulator), then set:"
echo "  MELONDS_DEVICE_LIB=... MELONDS_SIM_LIB=... MELONDS_HEADERS=..."
echo "and re-run this script to call xcodebuild -create-xcframework."
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode." >&2
  exit 1
fi

if [[ -z "${MELONDS_DEVICE_LIB:-}" || -z "${MELONDS_SIM_LIB:-}" || -z "${MELONDS_HEADERS:-}" ]]; then
  echo "Missing MELONDS_DEVICE_LIB / MELONDS_SIM_LIB / MELONDS_HEADERS — aborting until upstream libs exist."
  echo "Clone: git clone --depth 1 https://github.com/melonDS-emu/melonDS.git ~/src/melonDS"
  echo "See App/Vendor/melonDS.md."
  exit 2
fi

command -v xcodebuild >/dev/null

mkdir -p "$OUT"
rm -rf "$OUT/melonDS.xcframework"
xcodebuild -create-xcframework \
  -library "$MELONDS_DEVICE_LIB" -headers "$MELONDS_HEADERS" \
  -library "$MELONDS_SIM_LIB" -headers "$MELONDS_HEADERS" \
  -output "$OUT/melonDS.xcframework"

echo "Wrote $OUT/melonDS.xcframework"
echo "Next: enable RETROPLAY_HAS_MELONDS in project.yml / XCODE.md and implement MelonDSNativeDriver."

#!/usr/bin/env bash
# Build PPSSPP for iOS device + simulator and pack an XCFramework into
# App/Vendor/Output/PPSSPP.xcframework (gitignored).
#
# Run on a Mac with Xcode. Upstream iOS build is complex (ffmpeg, submodules).
# This script documents the intended layout; fill RETROPLAY_PPSSPP_* paths after
# a successful upstream ios build on the mini.
set -euo pipefail

ROOT="${RETROPLAY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="$ROOT/App/Vendor/Output"
PPSSPP_SRC="${PPSSPP_SRC:-$HOME/src/ppsspp}"

echo "RetroPlay PPSSPP XCFramework helper"
echo "  ROOT=$ROOT"
echo "  PPSSPP_SRC=$PPSSPP_SRC"
echo "  OUT=$OUT"
echo
echo "Upstream PPSSPP iOS builds are done from the ppsspp tree (b.sh / Xcode)."
echo "After you have device + sim static libs (or frameworks), set:"
echo "  PPSSPP_DEVICE_LIB=... PPSSPP_SIM_LIB=... PPSSPP_HEADERS=..."
echo "then re-run this script to call xcodebuild -create-xcframework."
echo

if [[ -z "${PPSSPP_DEVICE_LIB:-}" || -z "${PPSSPP_SIM_LIB:-}" || -z "${PPSSPP_HEADERS:-}" ]]; then
  echo "Missing PPSSPP_DEVICE_LIB / PPSSPP_SIM_LIB / PPSSPP_HEADERS — aborting until upstream libs exist."
  echo "Clone: git clone --recurse-submodules https://github.com/hrydgard/ppsspp.git ~/src/ppsspp"
  exit 2
fi

mkdir -p "$OUT"
rm -rf "$OUT/PPSSPP.xcframework"
xcodebuild -create-xcframework \
  -library "$PPSSPP_DEVICE_LIB" -headers "$PPSSPP_HEADERS" \
  -library "$PPSSPP_SIM_LIB" -headers "$PPSSPP_HEADERS" \
  -output "$OUT/PPSSPP.xcframework"

echo "Wrote $OUT/PPSSPP.xcframework"

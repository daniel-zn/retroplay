#!/usr/bin/env bash
# Build mupen64plus-next (+ GLideN64/GLES, cached_interpreter) for iOS and pack an
# XCFramework into App/Vendor/Output/mupen64plus.xcframework (gitignored).
#
# Run on a Mac with Xcode. Upstream iOS packaging varies by fork — this script
# documents the intended layout; fill MUPEN_* paths after a successful upstream build.
# Do not run on the Linux Grok Bot box. Do not enable dynarec or paraLLEl-RDP.
set -euo pipefail

ROOT="${RETROPLAY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="$ROOT/App/Vendor/Output"
MUPEN_SRC="${MUPEN_SRC:-${MUPEN64PLUS_SRC:-$HOME/src/mupen64plus-next}}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-18.0}"

echo "RetroPlay mupen64plus XCFramework helper"
echo "  ROOT=$ROOT"
echo "  MUPEN_SRC=$MUPEN_SRC"
echo "  OUT=$OUT"
echo "  DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
echo
echo "Target config: cached_interpreter + GLideN64/GLES (NOT paraLLEl-RDP, NOT dynarec)."
echo
echo "Build upstream for iphoneos (+ optional simulator), then set:"
echo "  MUPEN_DEVICE_LIB=... MUPEN_SIM_LIB=... MUPEN_HEADERS=..."
echo "and re-run this script to call xcodebuild -create-xcframework."
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode." >&2
  exit 1
fi

if [[ -z "${MUPEN_DEVICE_LIB:-}" || -z "${MUPEN_SIM_LIB:-}" || -z "${MUPEN_HEADERS:-}" ]]; then
  echo "Missing MUPEN_DEVICE_LIB / MUPEN_SIM_LIB / MUPEN_HEADERS — aborting until upstream libs exist."
  echo "Clone example: git clone --depth 1 https://github.com/libretro/mupen64plus-libretro-nx.git ~/src/mupen64plus-next"
  echo "See App/Vendor/mupen64plus.md."
  exit 2
fi

command -v xcodebuild >/dev/null

mkdir -p "$OUT"
rm -rf "$OUT/mupen64plus.xcframework"
xcodebuild -create-xcframework \
  -library "$MUPEN_DEVICE_LIB" -headers "$MUPEN_HEADERS" \
  -library "$MUPEN_SIM_LIB" -headers "$MUPEN_HEADERS" \
  -output "$OUT/mupen64plus.xcframework"

echo "Wrote $OUT/mupen64plus.xcframework"
echo "Next: enable RETROPLAY_HAS_N64 in project.yml / XCODE.md and implement N64NativeDriver."

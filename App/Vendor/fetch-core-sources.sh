#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Check out the exact emulator-core sources RetroPlay is built from (see SOURCES.md)
# next to this repository, and apply RetroPlay's patches.
#   ./fetch-core-sources.sh [destination]   (default: the folder containing retroplay/)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$(cd "$HERE/../../.." && pwd)}"

fetch() {
  local name="$1" url="$2" commit="$3" recurse="${4:-}"
  local dir="$DEST/$name"
  if [[ ! -d "$dir/.git" ]]; then
    git clone "$url" "$dir"
  fi
  git -C "$dir" fetch --quiet origin "$commit" || git -C "$dir" fetch --quiet origin
  git -C "$dir" checkout --quiet "$commit"
  if [[ -n "$recurse" ]]; then
    git -C "$dir" submodule update --init --recursive
  fi
  echo "$name @ $(git -C "$dir" rev-parse --short HEAD)"
}

fetch mgba https://github.com/mgba-emu/mgba.git aa6394c93ca24b0ff40dc9231bdb0533f415e0be
fetch melonDS https://github.com/melonDS-emu/melonDS.git 906e9ebb27da8c6a715cd7abab4abfe8a8d29427
fetch mupen64plus-next https://github.com/libretro/mupen64plus-libretro-nx.git f275caf4b2bfa1e6d1c51636746ea793f3d80320
fetch ppsspp https://github.com/hrydgard/ppsspp.git 98e70c8ca3435d532a059add0b4fb90a4a091248 recurse

# Header fixes are part of every build. The Makefile patch only retargets the ios-arm64
# branch at the Simulator and is applied with FOR_SIMULATOR=1 (never for device builds).
apply_patch() {
  local dir="$1" patch="$2"
  if git -C "$dir" apply --check "$patch" 2>/dev/null; then
    git -C "$dir" apply "$patch"
    echo "applied $(basename "$patch")"
  else
    echo "$(basename "$patch") already applied (or conflicts); check git -C $dir diff"
  fi
}
apply_patch "$DEST/mupen64plus-next" "$HERE/patches/mupen64plus-next-ios-headers.patch"
if [[ "${FOR_SIMULATOR:-0}" == "1" ]]; then
  apply_patch "$DEST/mupen64plus-next" "$HERE/patches/mupen64plus-next-ios-simulator.patch"
fi

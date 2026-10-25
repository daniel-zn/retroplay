#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Check out the exact emulator-core sources RetroPlay is built from (see SOURCES.md)
# into External/ in this repository (git-ignored), and apply RetroPlay's patches.
#   ./fetch-core-sources.sh [destination]   (default: External/ next to App/)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-$(cd "$HERE/../.." && pwd)/External}"
mkdir -p "$DEST"

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
# Libretro cores (build-libretro-cores-ios.sh). Submodules at the commits each records
# (pins/clownmdemu-libretro-submodules.txt, pins/pcsx_rearmed-submodules.txt).
fetch nestopia https://github.com/libretro/nestopia.git 135dfa6dfda5e7603d61e751b9ddd0cc42546bc3
fetch bsnes https://github.com/libretro/bsnes.git 63ee22f7af8f5d1ada295c2c98fd7bf261fa62a7
fetch prosystem-libretro https://github.com/libretro/prosystem-libretro.git 8a88014287c7a01cd568067e5a557d0a2b2a051f
fetch clownmdemu-libretro https://github.com/Clownacy/clownmdemu-libretro.git d43c2708b0a31c285ce16724b6c4a2e92af07346 recurse
fetch pcsx_rearmed https://github.com/libretro/pcsx_rearmed.git c8816799b50388e61cfe237fe2cdbb7d8175f20a recurse

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
apply_patch "$DEST/pcsx_rearmed" "$HERE/patches/pcsx_rearmed-no-ptrace.patch"
if [[ "${FOR_SIMULATOR:-0}" == "1" ]]; then
  apply_patch "$DEST/mupen64plus-next" "$HERE/patches/mupen64plus-next-ios-simulator.patch"
fi

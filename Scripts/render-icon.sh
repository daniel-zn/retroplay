#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Renders AppIcon.icon (the one source for the app icon) as PNGs, for previews and anything that
# needs a flat copy (website, docs). Nothing it writes is committed: run it again when the icon
# changes. Uses Icon Composer's headless renderer, which ships with Xcode.
#
#   Scripts/render-icon.sh [out-dir] [size]      (defaults: build/icon-renders, 1024)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/icon-renders}"; SIZE="${2:-1024}"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -x "$ICTOOL" ]] || { echo "Icon Composer's ictool not found (Xcode 26+ needed)"; exit 1; }
mkdir -p "$OUT"
for r in Default Dark TintedLight TintedDark ClearLight ClearDark; do
  "$ICTOOL" AppIcon.icon --export-image --output-file "$OUT/AppIcon-$r.png" --platform iOS \
    --rendition "$r" --width "$SIZE" --height "$SIZE" --scale 1 --tint-color 0.9 --tint-strength 0.7 >/dev/null
  echo "$OUT/AppIcon-$r.png"
done

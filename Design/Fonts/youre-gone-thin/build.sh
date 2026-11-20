#!/bin/bash
# Rebuilds You're Gone Thin (upright and italic) from source/ into the app's copies in
# AppHost/Supporting, validates both and draws the previews (preview/, not committed).
# Afterwards `git status AppHost/Supporting` shows whether the fonts' bytes changed.
# PY names a Python with fontTools, skia-pathops, Pillow and FontForge's module.
set -euo pipefail
cd "$(dirname "$0")"
PY="${PY:-python3}"
app=../../../AppHost/Supporting
mkdir -p preview
for style in Regular Italic; do
  "$PY" -I build.py --style "$style" --out "$app/YoureGoneThin-$style.otf"
  "$PY" -I validate.py "$app/YoureGoneThin-$style.otf"
done
"$PY" -I preview.py --overlay preview/overlay.png source/YoureGone-Regular.otf "$app/YoureGoneThin-Regular.otf"
"$PY" -I preview.py --overlay preview/overlay-italic.png source/YoureGone-Italic.otf "$app/YoureGoneThin-Italic.otf"
"$PY" -I preview.py preview/specimen.png \
  "ORIGINAL  You're Gone=source/YoureGone-Regular.otf" "THIN  You're Gone Thin (-26)=$app/YoureGoneThin-Regular.otf" \
  "ORIGINAL  You're Gone Italic=source/YoureGone-Italic.otf" "THIN  You're Gone Thin Italic (-26)=$app/YoureGoneThin-Italic.otf"

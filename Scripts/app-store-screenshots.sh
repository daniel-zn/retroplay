#!/bin/bash
# The App Store screenshots (AppStoreScreenshotsUITests) on the "RetroPlay Build" Simulator,
# copied to OUT (default build/app-store-screenshots) as <name>.png at 1320 x 2868 (6.9" iPhone).
#   app-store-screenshots.sh [OUT]
# Only free homebrew games may appear: the library is narrowed to HOMEBREW for the run (every
# other game file waits in a hidden folder in the app's data and library.json is filtered), then
# everything is put back as it was.
# Run it in the Simulator's turn line; it builds and tests in one go (Scripts/app-tests.sh).
set -u
cd "$(dirname "$0")/.."
OUT=${1:-build/app-store-screenshots}
HOMEBREW=(breakout.sfc sgdk-cube.bin full_game.nes SideBounce.a78 BForest.a78)
BUNDLE=com.danielzn.retroplay

s=$(xcrun simctl list devices | grep -F 'RetroPlay Build (' | grep -oE '[0-9A-F-]{36}' | head -1)
[ -n "$s" ] || { echo 'app-store-screenshots: no RetroPlay Build Simulator'; exit 1; }
# The app's data folder moves when the test run installs the app again, so it's looked up each
# time, and the other games wait inside it (a hidden folder the library doesn't read), not elsewhere.
container() {
  xcrun simctl boot "$s" 2>/dev/null; xcrun simctl bootstatus "$s" >/dev/null
  xcrun simctl get_app_container "$s" "$BUNDLE" data 2>/dev/null
}
ASIDE=Documents/Games/.app-store-aside
LIBRARY="Library/Application Support/library.json"
SAVED="$LIBRARY.app-store-saved"
restore() {
  local data; data=$(container)
  if [ -z "$data" ] || [ ! -d "$data/$ASIDE" ]; then
    echo "app-store-screenshots: RESTORE FAILED: no $ASIDE in the app's data folder ($data); put the games back by hand"
    return 1
  fi
  local f ok=yes
  for f in "$data/$ASIDE"/*; do [ -e "$f" ] && { mv "$f" "$data/Documents/Games/" || ok=no; }; done
  [ -f "$data/$SAVED" ] && { mv "$data/$SAVED" "$data/$LIBRARY" || ok=no; }
  # Only an emptied folder is removed: nothing is ever deleted that couldn't be put back.
  xcrun simctl shutdown "$s" 2>/dev/null
  if [ $ok = yes ]; then rmdir "$data/$ASIDE"; else
    echo "app-store-screenshots: RESTORE INCOMPLETE: what's left is in $data/$ASIDE"; return 1; fi
  echo "app-store-screenshots: library restored"
}

data=$(container)
[ -n "$data" ] || { echo "app-store-screenshots: RetroPlay isn't installed on the Simulator (no library)"; exit 1; }
[ -e "$data/$ASIDE" ] || [ -e "$data/$SAVED" ] && { echo "app-store-screenshots: $data/$ASIDE exists from an earlier run: restore it first"; exit 1; }
for f in "${HOMEBREW[@]}"; do
  [ -f "$data/Documents/Games/$f" ] || { echo "app-store-screenshots: $f missing from the Simulator's Games folder"; exit 1; }
done
mkdir -p "$data/$ASIDE"
trap restore EXIT
cp "$data/$LIBRARY" "$data/$SAVED"
for f in "$data/Documents/Games"/*; do
  name=$(basename "$f")
  keep=no
  for h in "${HOMEBREW[@]}"; do [ "$name" = "$h" ] && keep=yes; done
  [ $keep = yes ] || mv "$f" "$data/$ASIDE/"
done
python3 - "$data/$LIBRARY" "${HOMEBREW[@]}" <<'PY'
import json, sys
path, keep = sys.argv[1], set(sys.argv[2:])
rows = json.load(open(path))
json.dump([r for r in rows if r.get("relativePath") in keep], open(path, "w"))
PY

INTEGRATE_LOG_DIR=build Scripts/app-tests.sh appstore
r=$?
R=build/app-tests-appstore.xcresult
rm -rf "$OUT" build/appstore-attachments
mkdir -p "$OUT"
if [ -d "$R" ] && xcrun xcresulttool export attachments --path "$R" --output-path build/appstore-attachments >/dev/null; then
  python3 - build/appstore-attachments "$OUT" <<'PY'
import json, pathlib, shutil, sys
src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for test in json.load(open(src / "manifest.json")):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "")
        if name.startswith("appstore-"):
            stem = name[len("appstore-"):].split("_")[0].removesuffix(".png")   # drops "_0_<UUID>.png"
            shutil.copy(src / a["exportedFileName"], out / f"{stem}.png")
PY
fi
rm -rf build/appstore-attachments
ls -l "$OUT"
echo "app-store-screenshots: exit $r"
exit $r

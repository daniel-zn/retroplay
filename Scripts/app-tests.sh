#!/bin/bash
# RetroPlay's app tests (the RetroPlay scheme) on the "RetroPlay Build" Simulator: integrate's
# "app" and "screenshots" checks, also fine to run by hand from a checkout.
#   app-tests.sh             unit tests and the behavioural UI tests (every UI class but the
#                            screenshot sets below)
#   app-tests.sh screenshots the screenshot sets only (type, theme and layout review)
# APP_TESTS (app mode): UI tests to run, comma-separated, each a class of RetroPlayUITests or
# Class/testMethod; the unit tests always run with them. Unset: every behavioural test.
# Fails when a test it was given didn't run.
set -u
cd "$(dirname "$0")/.."
MODE=${1:-app}
SRC=${LAND_SOURCE:-${INTEGRATE_SOURCE:-}}
# The prebuilt cores and their sources aren't in git: linked from the main checkout, as the
# release does.
if [ -n "$SRC" ] && [ "$(cd "$SRC" && pwd)" != "$PWD" ]; then
  [ -e App/Vendor/Output ] || ln -sfn "$SRC/App/Vendor/Output" App/Vendor/Output
  [ -e External ] || ln -sfn "$SRC/External" External
fi
[ -d App/Vendor/Output ] && [ -d External ] || { echo "app-tests: App/Vendor/Output or External missing"; exit 1; }
xcodegen generate -q || { echo "app-tests: xcodegen failed"; exit 1; }

s=$(xcrun simctl list devices | grep -F 'RetroPlay Build (' | grep -oE '[0-9A-F-]{36}' | head -1)
[ -n "$s" ] || { echo 'app-tests: no RetroPlay Build Simulator'; exit 1; }
DD=build/dd-land/app
R="${LAND_LOG_DIR:-build}/app-tests-$MODE.xcresult"
rm -rf "$R"

# Screenshot sets: many launches across looks, for review rather than behaviour.
SCREENSHOT_CLASSES=(TypographyScreenshotsUITests LandscapeControlsLookUITests)
only=()
if [ "$MODE" = screenshots ]; then
  for c in "${SCREENSHOT_CLASSES[@]}"; do
    # Only the sets this checkout has (an -only-testing that matches nothing fails the run).
    grep -rqs "class $c\b" App/Tests/RetroPlayUITests && only+=("-only-testing:RetroPlayUITests/$c")
  done
  [ ${#only[@]} -gt 0 ] || { echo "app-tests: no screenshot sets here"; exit 0; }
elif [ -n "${APP_TESTS:-}" ]; then
  only+=(-only-testing:RetroPlayCoreTests)
  IFS=',' read -ra picks <<< "$APP_TESTS"
  for t in "${picks[@]}"; do only+=("-only-testing:RetroPlayUITests/$t"); done
else
  for c in "${SCREENSHOT_CLASSES[@]}"; do
    grep -rqs "class $c\b" App/Tests/RetroPlayUITests && only+=("-skip-testing:RetroPlayUITests/$c")
  done
fi

xcrun simctl boot "$s" 2>/dev/null; xcrun simctl bootstatus "$s" >/dev/null
xcodebuild build-for-testing -project RetroPlay.xcodeproj -scheme RetroPlay -destination id=$s -derivedDataPath "$DD" -quiet
r=$?
if [ $r -eq 0 ]; then
  # The cores' frameworks are re-signed for the Simulator, or the UI test host stops in dyld.
  ( cd "$DD/Build/Products/Debug-iphonesimulator" && for f in *.framework; do codesign -f -s - "$f" >/dev/null 2>&1; done )
  # A fresh Simulator for the run: after a long build its services can be gone.
  xcrun simctl shutdown "$s" 2>/dev/null; xcrun simctl boot "$s"; xcrun simctl bootstatus "$s" >/dev/null
  run_tests() {
    rm -rf "$R"
    xcodebuild test-without-building -project RetroPlay.xcodeproj -scheme RetroPlay -destination id=$s -derivedDataPath "$DD" \
      ${only[@]+"${only[@]}"} -resultBundlePath "$R" -collect-test-diagnostics never 2>&1 | tee "$R.log"
    return ${PIPESTATUS[0]}
  }
  run_tests
  r=$?
  # The Simulator's services can die under memory pressure before the runner starts ("Failed to
  # install or launch the test runner", no UI test run; the unit tests may have). That's the machine, not a test: the
  # Simulator is restarted and the tests run once more. A test that ran and failed is final.
  if [ $r -ne 0 ] && grep -q "Failed to install or launch the test runner" "$R.log" && ! grep -q "Test Case '-\[RetroPlayUITests\..*' started" "$R.log"; then
    echo "app-tests: the test runner didn't start (no test ran); restarting the Simulator and running the tests again"
    xcrun simctl shutdown "$s" 2>/dev/null; sleep 5; xcrun simctl boot "$s"; xcrun simctl bootstatus "$s" >/dev/null
    run_tests
    r=$?
  fi
fi
xcrun simctl shutdown "$s" 2>/dev/null

if [ "$MODE" = app ] && [ -n "${APP_TESTS:-}" ]; then
  if [ ! -d "$R" ]; then
    echo "app-tests: no results, so the chosen tests didn't run"
    exit 1
  fi
  xcrun xcresulttool get test-results tests --path "$R" > "$R.tests.json" 2>/dev/null
  python3 - "$R.tests.json" "$APP_TESTS" <<'PY' || r=1
import json, sys
def walk(node, path, seen):
    name = node.get("name", "")
    kind = node.get("nodeType", "")
    here = path + [name]
    if kind == "Test Case":
        cls = path[-1] if path else ""
        seen.add(cls)
        seen.add(f"{cls}/{name.split('(')[0]}")
    for child in node.get("children", []):
        walk(child, here, seen)
seen = set()
for node in json.load(open(sys.argv[1])).get("testNodes", []):
    walk(node, [], seen)
missing = [t for t in sys.argv[2].split(",") if t and t not in seen]
if missing:
    print("app-tests: chosen tests that didn't run:", ", ".join(missing))
    sys.exit(1)
PY
fi
echo "app-tests: exit $r"
exit $r

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Package the mupen64plus-next libretro dylibs as an XCFramework of real .framework
# bundles. App Store Connect rejects bare .dylib files inside the app (ITMS-90171), so
# the embedded core must be a framework with an Info.plist and a framework install name.
#
# Usage:
#   MUPEN_DEVICE_LIB=… MUPEN_SIM_LIB=… MUPEN_HEADERS=… ./package-mupen64plus-framework.sh
# With no variables it repackages the dylibs from an existing Output/mupen64plus.xcframework.
set -euo pipefail

ROOT="${RETROPLAY_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="$ROOT/App/Vendor/Output"
XCF="$OUT/mupen64plus.xcframework"
MIN_IOS="${DEPLOYMENT_TARGET:-26.0}"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
NAME="mupen64plus"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "${MUPEN_DEVICE_LIB:-}" ]]; then
  MUPEN_DEVICE_LIB="$(ls "$XCF"/ios-arm64/*.dylib 2>/dev/null | head -1 || true)"
  MUPEN_SIM_LIB="$(ls "$XCF"/ios-arm64-simulator/*.dylib 2>/dev/null | head -1 || true)"
  MUPEN_HEADERS="$XCF/ios-arm64/Headers"
fi
for f in "${MUPEN_DEVICE_LIB:-}" "${MUPEN_SIM_LIB:-}"; do
  [[ -f "$f" ]] || { echo "Missing dylib: '$f' (set MUPEN_DEVICE_LIB / MUPEN_SIM_LIB)" >&2; exit 2; }
done
cp "$MUPEN_DEVICE_LIB" "$WORK/device.dylib"
cp "$MUPEN_SIM_LIB" "$WORK/sim.dylib"
mkdir -p "$WORK/headers" && cp -R "$MUPEN_HEADERS"/. "$WORK/headers/"

make_framework() {
  local lib="$1" platform="$2" plist_platform="$3" dest="$4"
  local fw="$dest/$NAME.framework"
  mkdir -p "$fw/Headers"
  cp -R "$WORK/headers"/. "$fw/Headers/"
  # Binary: framework install name, and a build-version load command matching the
  # Info.plist MinimumOSVersion (the device dylib shipped with LC_VERSION_MIN_IPHONEOS 8.0).
  vtool -set-build-version "$platform" "$MIN_IOS" "$SDK_VERSION" -replace -output "$fw/$NAME" "$lib"
  install_name_tool -id "@rpath/$NAME.framework/$NAME" "$fw/$NAME"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.danielzn.retroplay.mupen64plus</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$plist_platform</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>$MIN_IOS</string>
</dict>
</plist>
PLIST
}

make_framework "$WORK/device.dylib" ios iPhoneOS "$WORK/device"
make_framework "$WORK/sim.dylib" iossim iPhoneSimulator "$WORK/sim"

rm -rf "$XCF"
xcodebuild -create-xcframework \
  -framework "$WORK/device/$NAME.framework" \
  -framework "$WORK/sim/$NAME.framework" \
  -output "$XCF" >/dev/null
echo "Wrote $XCF"

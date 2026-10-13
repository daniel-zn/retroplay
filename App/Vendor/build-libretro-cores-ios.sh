#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the libretro cores RetroPlay loads at runtime (NES, SNES, Atari 7800, Genesis, PS1)
# for iPhone and the Simulator, and package each as Output/<name>.xcframework of real
# .framework bundles (App Store Connect rejects bare .dylib files, ITMS-90171).
#
# The sources come from fetch-core-sources.sh (commits in SOURCES.md).
#   SRC=<folder with the checkouts> ./build-libretro-cores-ios.sh [core …]
# Cores: nestopia bsnes prosystem clownmdemu pcsx_rearmed (default: all).
# No core is built with a JIT/dynarec: iOS apps can't map executable memory.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/Output"
SRC="${SRC:-$(cd "$HERE/../../.." && pwd)}"
MIN_IOS="${DEPLOYMENT_TARGET:-26.0}"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
JOBS="$(sysctl -n hw.ncpu)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# source dir | make dir (relative) | make args | built dylib (relative to make dir) | extra compiler flags
core_spec() {
  case "$1" in
    nestopia) echo "nestopia|libretro||nestopia_libretro_ios.dylib" ;;
    # Newer libc++ refuses nall's is_signed<int128_t> specialisations; they're harmless here.
    bsnes) echo "bsnes|.|IPHONEMINVER=|bsnes_libretro_ios.dylib|-Wno-invalid-specialization" ;;
    prosystem) echo "prosystem-libretro|.||prosystem_libretro_ios.dylib" ;;
    clownmdemu) echo "clownmdemu-libretro|.||clownmdemu_libretro_ios.dylib" ;;
    # -DRETROPLAY turns off the PTRACE_TRACEME call (patches/pcsx_rearmed-no-ptrace.patch).
    pcsx_rearmed) echo "pcsx_rearmed|.|-f Makefile.libretro MINVERSION= DYNAREC=0|pcsx_rearmed_libretro_ios.dylib|-DRETROPLAY" ;;
    *) echo "unknown core $1" >&2; exit 2 ;;
  esac
}

build_slice() {
  local name="$1" slice="$2"
  IFS='|' read -r dir sub args lib extra <<<"$(core_spec "$name")"
  local sdk target
  if [[ "$slice" == device ]]; then
    sdk=iphoneos; target="arm64-apple-ios$MIN_IOS"
  else
    sdk=iphonesimulator; target="arm64-apple-ios$MIN_IOS-simulator"
  fi
  local sysroot cc cxx
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" -f clang) -target $target -isysroot $sysroot ${extra:-}"
  cxx="$(xcrun --sdk "$sdk" -f clang++) -target $target -isysroot $sysroot ${extra:-}"
  local mdir="$SRC/$dir/$sub"
  echo "== $name ($slice)"
  # shellcheck disable=SC2086
  make -C "$mdir" $args platform=ios-arm64 clean >/dev/null 2>&1 || true
  # Command-line CC/CXX override the Makefiles' own iOS compiler lines (device-only flags).
  # shellcheck disable=SC2086
  make -C "$mdir" $args platform=ios-arm64 IOSSDK="$sysroot" CC="$cc" CXX="$cxx" \
    -j"$JOBS" >"$WORK/$name-$slice.log" 2>&1 || {
      tail -40 "$WORK/$name-$slice.log" >&2
      echo "build failed: $name ($slice)" >&2
      exit 1
    }
  cp "$mdir/$lib" "$WORK/$name-$slice.dylib"
  # shellcheck disable=SC2086
  make -C "$mdir" $args platform=ios-arm64 clean >/dev/null 2>&1 || true
}

make_framework() {
  local name="$1" lib="$2" platform="$3" plist_platform="$4" dest="$5"
  local fw="$dest/$name.framework"
  mkdir -p "$fw"
  vtool -set-build-version "$platform" "$MIN_IOS" "$SDK_VERSION" -replace -output "$fw/$name" "$lib"
  install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name"
  strip -x "$fw/$name" 2>/dev/null || true
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>com.danielzn.retroplay.$(echo "$name" | tr '_' '-')</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$name</string>
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

CORES=("$@")
[[ ${#CORES[@]} -gt 0 ]] || CORES=(nestopia bsnes prosystem clownmdemu pcsx_rearmed)
mkdir -p "$OUT"
for name in "${CORES[@]}"; do
  build_slice "$name" device
  build_slice "$name" simulator
  make_framework "$name" "$WORK/$name-device.dylib" ios iPhoneOS "$WORK/$name/device"
  make_framework "$name" "$WORK/$name-simulator.dylib" iossim iPhoneSimulator "$WORK/$name/sim"
  rm -rf "$OUT/$name.xcframework"
  xcodebuild -create-xcframework \
    -framework "$WORK/$name/device/$name.framework" \
    -framework "$WORK/$name/sim/$name.framework" \
    -output "$OUT/$name.xcframework" >/dev/null
  echo "Wrote $OUT/$name.xcframework ($(du -sh "$OUT/$name.xcframework/ios-arm64/$name.framework/$name" | cut -f1) device)"
done

#!/usr/bin/env bash
# Build static libmgba for iOS device + simulator and pack an XCFramework.
# Run on a Mac with Xcode + CMake + Ninja. Do not run on the Linux Grok Bot box.
set -euo pipefail

RETROPLAY_ROOT="${RETROPLAY_ROOT:-}"
MGBA_SRC="${MGBA_SRC:-}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-18.0}"

if [[ -z "${RETROPLAY_ROOT}" || -z "${MGBA_SRC}" ]]; then
  echo "Set RETROPLAY_ROOT (path to daniel-zn/retroplay) and MGBA_SRC (path to mgba-emu/mgba clone)." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode." >&2
  exit 1
fi

command -v cmake >/dev/null
command -v xcodebuild >/dev/null
command -v ninja >/dev/null || { echo "Install Ninja (brew install ninja)."; exit 1; }

OUT="${RETROPLAY_ROOT}/App/Vendor/Output"
HEADERS_STAGE="${OUT}/headers"
DEVICE_BUILD="${MGBA_SRC}/build-ios-device"
SIM_BUILD="${MGBA_SRC}/build-ios-sim"
mkdir -p "${OUT}" "${HEADERS_STAGE}"

COMMON_FLAGS=(
  -G Ninja
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}"
  -DCMAKE_BUILD_TYPE=Release
  -DLIBMGBA_ONLY=ON
  -DM_CORE_GBA=ON
  -DM_CORE_GB=OFF
  -DBUILD_STATIC=ON
  -DBUILD_SHARED=OFF
  -DBUILD_QT=OFF
  -DBUILD_SDL=OFF
  -DBUILD_LIBRETRO=OFF
  -DDISABLE_DEPS=ON
  -DENABLE_SCRIPTING=OFF
  -DENABLE_DEBUGGERS=OFF
)

echo "== Configure device =="
cmake -S "${MGBA_SRC}" -B "${DEVICE_BUILD}" \
  "${COMMON_FLAGS[@]}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos

echo "== Configure simulator =="
cmake -S "${MGBA_SRC}" -B "${SIM_BUILD}" \
  "${COMMON_FLAGS[@]}" \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphonesimulator

echo "== Build =="
cmake --build "${DEVICE_BUILD}"
cmake --build "${SIM_BUILD}"

find_lib() {
  local dir="$1"
  local found
  found="$(find "${dir}" -name 'libmgba.a' -o -name 'libmgba-static.a' | head -1 || true)"
  if [[ -z "${found}" ]]; then
    echo "Could not find libmgba.a under ${dir}" >&2
    find "${dir}" -name '*.a' | head -20 >&2 || true
    exit 1
  fi
  echo "${found}"
}

DEVICE_LIB="$(find_lib "${DEVICE_BUILD}")"
SIM_LIB="$(find_lib "${SIM_BUILD}")"
echo "Device lib: ${DEVICE_LIB}"
echo "Sim lib:    ${SIM_LIB}"

echo "== Stage headers =="
rm -rf "${HEADERS_STAGE:?}/"*
mkdir -p "${HEADERS_STAGE}/mgba" "${HEADERS_STAGE}/mgba-util"
cp -R "${MGBA_SRC}/include/mgba/." "${HEADERS_STAGE}/mgba/"
cp -R "${MGBA_SRC}/include/mgba-util/." "${HEADERS_STAGE}/mgba-util/"
# Prefer generated flags.h from device build
if [[ -f "${DEVICE_BUILD}/include/mgba/flags.h" ]]; then
  cp "${DEVICE_BUILD}/include/mgba/flags.h" "${HEADERS_STAGE}/mgba/flags.h"
elif [[ -f "${SIM_BUILD}/include/mgba/flags.h" ]]; then
  cp "${SIM_BUILD}/include/mgba/flags.h" "${HEADERS_STAGE}/mgba/flags.h"
fi

XCF="${OUT}/mGBA.xcframework"
rm -rf "${XCF}"
echo "== Create XCFramework =="
xcodebuild -create-xcframework \
  -library "${DEVICE_LIB}" -headers "${HEADERS_STAGE}" \
  -library "${SIM_LIB}" -headers "${HEADERS_STAGE}" \
  -output "${XCF}"

echo "Done: ${XCF}"
echo "Next: add the XCFramework to the iOS app target and implement MGBACore native calls."

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# MoltenVK (Vulkan on Metal, Apache-2.0) for PPSSPP's GPU renderer: downloads the official
# release, checks it, and writes App/Vendor/Output/MoltenVK.xcframework (gitignored) with the
# static libraries for iOS devices and the iOS Simulator. Unmodified upstream binaries.
set -euo pipefail

VERSION=v1.4.2
TAR_SHA256=562a15a29bc358446a56a4091c5f7e08f604184187c1d34f712148b61ef17276
DEVICE_SHA256=245e7e05926c55ae97ace1b1822190139d87bda5aaefbcfd2f5156e1287f448b
SIM_SHA256=e26e33c6e93be5f9f9e7c32ca268cf87b2d24a6f16352e4dbac0af77f73a0f6a

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/App/Vendor/Output/MoltenVK.xcframework"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fL --retry 3 -o "$WORK/MoltenVK-all.tar" \
  "https://github.com/KhronosGroup/MoltenVK/releases/download/$VERSION/MoltenVK-all.tar"
echo "$TAR_SHA256  $WORK/MoltenVK-all.tar" | shasum -a 256 -c -
tar -xf "$WORK/MoltenVK-all.tar" -C "$WORK" MoltenVK/MoltenVK/static/MoltenVK.xcframework
LIBS="$WORK/MoltenVK/MoltenVK/static/MoltenVK.xcframework"
echo "$DEVICE_SHA256  $LIBS/ios-arm64/libMoltenVK.a" | shasum -a 256 -c -
echo "$SIM_SHA256  $LIBS/ios-arm64_x86_64-simulator/libMoltenVK.a" | shasum -a 256 -c -

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
xcodebuild -create-xcframework \
  -library "$LIBS/ios-arm64/libMoltenVK.a" \
  -library "$LIBS/ios-arm64_x86_64-simulator/libMoltenVK.a" \
  -output "$OUT"
echo "Wrote $OUT (MoltenVK $VERSION)"

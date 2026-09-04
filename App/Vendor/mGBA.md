# Vendoring mGBA (M1) — exact Mac / Xcode steps

RetroPlay’s GBA path uses **[mGBA](https://mgba.io/)** ([mgba-emu/mgba](https://github.com/mgba-emu/mgba), **MPL 2.0**).

This file is the procedure for building **`libmgba` as a static library / XCFramework** and linking it into RetroPlay. It does **not** claim a prebuilt binary exists in this repo.

## Rules

1. Do **not** commit the full mGBA source tree into `daniel-zn/retroplay` until Daniel asks (keep git lean).
2. Build on a **Mac with Xcode** (miniMac or a laptop). Do **not** clone bulky trees onto the Linux Grok Bot box.
3. Keep MPL 2.0 attribution in the app acknowledgements.
4. Product path is App Store–safe: no JIT fantasy; mGBA’s interpreter is fine for GBA.

## Upstream knobs (from mGBA `CMakeLists.txt`)

When `LIBMGBA_ONLY` is set (or equivalent flags), upstream forces:

- `DISABLE_FRONTENDS` → no Qt / SDL
- `DISABLE_DEPS` → no FFmpeg / Discord / etc.
- `BUILD_STATIC=ON`, `BUILD_SHARED=OFF`
- `M_CORE_GBA` / `M_CORE_GB` on by default

Public headers install under `include/mgba/` and `include/mgba-util/`. Generated `include/mgba/flags.h` comes from the build.

Useful C entry points (see `include/mgba/core/core.h`):

| API | Role |
|-----|------|
| `mCoreFind` / `mCoreFindVF` / `mCoreCreate` | Create core for a ROM / platform |
| `mCoreLoadFile` / `mCoreLoadSaveFile` | Load ROM / save |
| `mCoreAutoloadSave` | SRAM |
| `mCoreSaveState` / `mCoreLoadState` | Save states |
| `struct mCore` vtable | `reset`, `runFrame`, video/audio buffers, keys |

Wire those from `MGBACore` via a thin Swift/C bridging header once `libmgba` is linked.

## Prerequisites (Mac)

- Xcode 26+ (or current Xcode with iOS SDK; Liquid Glass UI is separate from the C core)
- CMake ≥ 3.12 (`brew install cmake`)
- Command Line Tools / iOS device + simulator SDKs installed

Clone **outside** this repo, e.g.:

```bash
mkdir -p ~/src && cd ~/src
git clone --depth 1 https://github.com/mgba-emu/mgba.git
cd mgba
```

## Build script

Use `App/Vendor/build-mgba-ios.sh` from a Mac (paths relative to this repo). Example:

```bash
# From a Mac, with RETROPLAY_ROOT pointing at a checkout of daniel-zn/retroplay
export RETROPLAY_ROOT=~/src/retroplay
export MGBA_SRC=~/src/mgba
"$RETROPLAY_ROOT/App/Vendor/build-mgba-ios.sh"
```

The script:

1. Configures CMake twice: **iphoneos** (arm64) and **iphonesimulator** (arm64).
2. Builds static `libmgba.a` with frontends/deps off.
3. Stages headers (`include/mgba`, `include/mgba-util`, generated `flags.h`).
4. Runs `xcodebuild -create-xcframework` → `App/Vendor/Output/mGBA.xcframework` (gitignored locally; do not commit the XCFramework until Daniel asks).

### Manual CMake (same flags the script uses)

Device:

```bash
cmake -S "$MGBA_SRC" -B "$MGBA_SRC/build-ios-device" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBMGBA_ONLY=ON \
  -DM_CORE_GBA=ON \
  -DM_CORE_GB=OFF \
  -DBUILD_STATIC=ON \
  -DBUILD_SHARED=OFF \
  -DBUILD_QT=OFF \
  -DBUILD_SDL=OFF \
  -DBUILD_LIBRETRO=OFF \
  -DDISABLE_DEPS=ON \
  -DENABLE_SCRIPTING=OFF \
  -DENABLE_DEBUGGERS=OFF
cmake --build "$MGBA_SRC/build-ios-device" --config Release
```

Simulator (Apple Silicon):

```bash
cmake -S "$MGBA_SRC" -B "$MGBA_SRC/build-ios-sim" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBMGBA_ONLY=ON \
  -DM_CORE_GBA=ON \
  -DM_CORE_GB=OFF \
  -DBUILD_STATIC=ON \
  -DBUILD_SHARED=OFF \
  -DBUILD_QT=OFF \
  -DBUILD_SDL=OFF \
  -DBUILD_LIBRETRO=OFF \
  -DDISABLE_DEPS=ON \
  -DENABLE_SCRIPTING=OFF \
  -DENABLE_DEBUGGERS=OFF
cmake --build "$MGBA_SRC/build-ios-sim" --config Release
```

Locate `libmgba.a` under each build dir (CMake places the static target as `mgba` / `libmgba.a` depending on generator). Then:

```bash
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" -headers "$HEADERS_STAGE" \
  -library "$SIM_LIB" -headers "$HEADERS_STAGE" \
  -output "$RETROPLAY_ROOT/App/Vendor/Output/mGBA.xcframework"
```

If `-create-xcframework` complains about missing platform metadata in the `.a`, rebuild with correct `CMAKE_OSX_SYSROOT` / `CMAKE_SYSTEM_PROCESSOR` (see Apple forums notes on simulator static libs).

## Link into RetroPlay (Xcode)

Preferred for M1: an **iOS App** target (not only the Swift package), because document picker + sandbox Documents need an app container.

1. Open or create an iOS app that depends on the local `App/Package.swift` (`RetroPlayCore`).
2. Add `App/Vendor/Output/mGBA.xcframework` to the app target → **Frameworks, Libraries, and Embedded Content** (Do Not Embed for a static XCFramework is typical).
3. Add a bridging header (or `@_cdecl` module map later) that `#include <mgba/core/core.h>` and related headers from the XCFramework.
4. Implement `MGBACore` native path: `mCoreFind` → `mCoreLoadFile` → run loop calling `core->runFrame` → copy video buffer into a `MTKView` / `CIImage` / bitmap view; map Game Controller / touch into `core->setKeys`.
5. Leave `CoreFactory.makeCore(for: .gba)` returning `MGBACore()` (already does).

### SPM note

SwiftPM cannot comfortably compile the full mGBA CMake tree in-repo without vendoring sources. **Do not** add mGBA as a remote SPM package unless upstream publishes one. Use **XCFramework + app target** for M1. Optional later: binary SPM target that points at a released XCFramework artifact.

## Acceptance for M1

- Import a user-owned `.gba` via Files.
- Tap game → playable frames (not `notImplemented`).
- Pause / resume; SRAM save/load via `mCoreAutoloadSave` / save file APIs.
- No ROM dumps in git; no bulky mGBA tree committed unless Daniel asks.

## Who runs this

- **Docs / Swift stubs:** RetroPlay bot on Linux (this repo).
- **Actual CMake + Xcode link:** Daniel’s **Mac mini (miniMac)** or another Mac. Ask Engineer to loop **miniMac** rather than cloning mGBA onto the Grok Bot Linux box.

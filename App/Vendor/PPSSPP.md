# PPSSPP (PlayStation Portable)

RetroPlay's PSP core is [PPSSPP](https://www.ppsspp.org) ([hrydgard/ppsspp](https://github.com/hrydgard/ppsspp),
GPL-2.0-or-later). The exact revision and submodule states are in [`SOURCES.md`](SOURCES.md).

- CPU: IR interpreter (`CPUCore = 2`), no JIT, as iOS requires. See `PPSSPPDefaults`.
- Software GPU, captured to RGBA for the app's renderer.

## Build

1. `App/Vendor/fetch-core-sources.sh` checks out PPSSPP with its submodules next to this repo.
2. Build for `iphoneos` with PPSSPP's CMake iOS toolchain
   (`cmake -DCMAKE_TOOLCHAIN_FILE=./cmake/Toolchains/ios.cmake -DIOS_PLATFORM=OS …`, see the
   [PPSSPP build instructions](https://github.com/hrydgard/ppsspp/wiki/Build-instructions)) and
   merge the static libraries (Core, dependencies and the prebuilt FFmpeg) into one.
3. Package it with `PPSSPP_DEVICE_LIB=… PPSSPP_SIM_LIB=… PPSSPP_HEADERS=… App/Vendor/build-ppsspp-ios.sh`,
   which writes `App/Vendor/Output/PPSSPP.xcframework`.

PPSSPP's prebuilt FFmpeg libraries are device-only; a Simulator build needs FFmpeg rebuilt for
the Simulator.

## Integration

- C++ bridge: `AppHost/Sources/RetroPlayPPSSPPBridge.{h,mm}`; Swift driver
  `AppHost/Sources/PPSSPPNativeDriver.swift` (`RETROPLAY_HAS_PPSSPP`).
- Header search paths expect the PPSSPP checkout next to this repo (`../ppsspp`).
- PPSSPP's runtime data (PPGe atlas, VFPU tables, `compat.ini`, …) is bundled from
  `AppHost/Supporting/assets/` (see `SOURCE.md` there).

## Troubleshooting a black screen

1. After `PSP_Init`, and after every host frame, the host must set `coreState = CORE_RUNNING_CPU`
   (PPSSPP leaves `CORE_NEXTFRAME`), as PPSSPP's own frontends do; otherwise frames don't advance.
2. Software-GPU display buffers are often 16-bit: export with `ConvertBufferToScreenshot`, not a raw
   RGBA copy. `GetOutputFramebuffer` fails until the game calls `sceDisplaySetFrameBuf`.
3. In the Simulator, `vm_remap failed` / `Failed at view N` lines are memory-map probing; if init
   completes they're harmless.

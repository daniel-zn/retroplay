# PPSSPP (PSP) — Mac build + link

**Status (2026-09-08):** Swift host (`PPSSPPCore`, registry, AppHost stubs) on main. XCFramework is **Mac-only** (not in git), same pattern as mGBA.

## App Store rule

- **IR caching interpreter only** (`CPUCore = 2`). No dynarec / JIT.
- Snippet: see `PPSSPPDefaults.appStoreIniSnippet`.


## Build order (2026-09-08)

1. **Device (`IOS_PLATFORM=OS`) first.** Upstream Simulator iOS builds are historically unsupported ([ppsspp#18020](https://github.com/hrydgard/ppsspp/issues/18020)). Do not block PSP on sim.
2. Generate Xcode: `cmake -DCMAKE_TOOLCHAIN_FILE=./cmake/Toolchains/ios.cmake -DIOS_PLATFORM=OS -H. -Bbuild.ios -GXcode` (or `./b.sh --ios-xcode`).
3. Build iphoneos Release; collect static libs (`Core` + ffmpeg prebuilts + deps).
4. Optional later: try `IOS_PLATFORM=SIMULATOR`. If it fails, ship **ios-arm64-only** XCFramework and smoke ATV on a **physical device**.

### Simulator ffmpeg note (2026-09-08)

Upstream `ffmpeg/ios/universal/lib/*.a` are **iphoneos**. Linking them into an `IOS_PLATFORM=SIMULATOR` build fails (`building for iOS-simulator, but linking … built for iOS`). Rebuild ffmpeg for simulator only if you need sim; otherwise ship **ios-arm64** XCFramework and smoke on device.

5. Only then enable `RETROPLAY_HAS_PPSSPP` in `project.yml` and implement the native bridge.

## Mac mini checklist

1. Clone upstream **outside** retroplay:
   ```bash
   git clone --recurse-submodules https://github.com/hrydgard/ppsspp.git /Users/danielsmacmini/GitHub/ppsspp
   cd /Users/danielsmacmini/GitHub/ppsspp && git submodule update --init --recursive
   ```
2. Follow upstream iOS build docs: https://www.ppsspp.org/docs/reference/ios-support/ and https://github.com/hrydgard/ppsspp/wiki/Build-instructions (`b.sh` / Xcode).
3. Prefer producing a **static** library or framework for ios-arm64 + simulator, then:
   ```bash
   xcodebuild -create-xcframework \
     -library <device/lib….a> -headers <headers> \
     -library <sim/lib….a> -headers <headers> \
     -output /Users/danielsmacmini/GitHub/retroplay/App/Vendor/Output/PPSSPP.xcframework
   ```
   Helper stub: `App/Vendor/build-ppsspp-ios.sh` (fills in once paths are known on the mini).
4. XcodeGen / `project.yml`: add `PPSSPP.xcframework` dependency, `RETROPLAY_HAS_PPSSPP` compile condition (alongside mGBA).
5. App init already calls `PPSSPPNativeBootstrap.registerIfAvailable()`.
6. Implement real `PPSSPPNativeDriver` load/runFrame (C++ bridge) — until then `#if RETROPLAY_HAS_PPSSPP` still throws a clear “bridge not implemented” error.
7. Smoke: inject miniNAS `ATV Offroad Fury Pro UCUS98648.iso` → sim Documents (never commit).

## Product bot vs miniMac

- Product bot lands Swift + docs on GitHub.
- **miniMac** builds the XCFramework on the Mac mini and wires Xcode.


## RETROPLAY_HAS_PPSSPP wiring (2026-09-08)

- `project.yml` links `App/Vendor/Output/PPSSPP.xcframework` and defines `RETROPLAY_HAS_PPSSPP`.
- C bridge: `AppHost/Sources/RetroPlayPPSSPPBridge.{h,mm}` → Swift `PPSSPPNativeDriver`.
- Header search paths expect sibling checkout: `/Users/danielsmacmini/GitHub/ppsspp`.
- First boot attempts `NativeInit` + `PSP_Init` with **IR interpreter** + **software GPU** for RGBA capture.
- If compile/link fails on miniMac, iterate symbol/include fixes; do not commit the XCFramework.

## Troubleshooting: Play shows “Running” but black screen

1. **Fake status:** Play used to set “Running” as soon as `start()` returned. It now shows “Waiting for first frame…” until the frame sink gets pixels, then alerts after ~10s if still empty.
2. **coreState:** After `PSP_Init`, the host must set `coreState = CORE_RUNNING_CPU`. After each host frame PPSSPP leaves `CORE_NEXTFRAME`; reset to `CORE_RUNNING_CPU` before the next `PSP_RunLoop*` (same as EmuScreen / libretro). Without that, ticks no-op and SoftGPU never gets a display framebuffer.
3. **RGBA export:** SoftGPU display buffers are often 16-bit. Use `ConvertBufferToScreenshot` (not raw `memcpy` as RGBA8888). `GetOutputFramebuffer` also fails until `sceDisplaySetFrameBuf`.
4. **Simulator MemMap:** Many `vm_remap failed` / `Failed at view N` lines mean probing; if Init still completes, continue. Persistent MemMap failure blocks real frames — prefer device smoke for ATV.

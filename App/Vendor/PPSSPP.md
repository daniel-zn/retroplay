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
5. Only then enable `RETROPLAY_HAS_PPSSPP` in `project.yml` and implement the native bridge.

## Mac mini checklist

1. Clone upstream **outside** retroplay:
   ```bash
   git clone --recurse-submodules https://github.com/hrydgard/ppsspp.git ~/src/ppsspp
   cd ~/src/ppsspp && git submodule update --init --recursive
   ```
2. Follow upstream iOS build docs: https://www.ppsspp.org/docs/reference/ios-support/ and https://github.com/hrydgard/ppsspp/wiki/Build-instructions (`b.sh` / Xcode).
3. Prefer producing a **static** library or framework for ios-arm64 + simulator, then:
   ```bash
   xcodebuild -create-xcframework \
     -library <device/lib….a> -headers <headers> \
     -library <sim/lib….a> -headers <headers> \
     -output ~/src/retroplay/App/Vendor/Output/PPSSPP.xcframework
   ```
   Helper stub: `App/Vendor/build-ppsspp-ios.sh` (fills in once paths are known on the mini).
4. XcodeGen / `project.yml`: add `PPSSPP.xcframework` dependency, `RETROPLAY_HAS_PPSSPP` compile condition (alongside mGBA).
5. App init already calls `PPSSPPNativeBootstrap.registerIfAvailable()`.
6. Implement real `PPSSPPNativeDriver` load/runFrame (C++ bridge) — until then `#if RETROPLAY_HAS_PPSSPP` still throws a clear “bridge not implemented” error.
7. Smoke: inject miniNAS `ATV Offroad Fury Pro UCUS98648.iso` → sim Documents (never commit).

## Product bot vs miniMac

- Product bot lands Swift + docs on GitHub.
- **miniMac** builds the XCFramework on the Mac mini and wires Xcode.

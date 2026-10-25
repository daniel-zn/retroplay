# melonDS (Nintendo DS)

RetroPlay's DS core is [melonDS](https://melonds.kuribo64.net)
([melonDS-emu/melonDS](https://github.com/melonDS-emu/melonDS), GPL-3.0-or-later). The exact
revision is in [`SOURCES.md`](SOURCES.md).

- Interpreter only (no JIT), as iOS requires. OpenGL renderer and Qt frontend are off.
- Direct boot without BIOS/firmware works for most games.

## Build

Requires Xcode, CMake and Ninja.

1. `App/Vendor/fetch-core-sources.sh` checks out melonDS into `External/` (git-ignored).
2. Build melonDS's core as a static library for `iphoneos` and the Simulator with CMake
   (`ENABLE_JIT=OFF`, `ENABLE_OGLRENDERER=OFF`, `BUILD_QT_SDL=OFF`) into `build-ios-device/` and
   `build-ios-sim/` inside the melonDS checkout.
3. Package it:

   ```bash
   MELONDS_DEVICE_LIB=… MELONDS_SIM_LIB=… MELONDS_HEADERS=… App/Vendor/build-melonds-ios.sh
   ```

   which writes `App/Vendor/Output/melonDS.xcframework`.

## Integration

- C++ bridge: `AppHost/Sources/MelonDS/` (`MelonDSBridge.cpp`, `Platform_ios.cpp`); Swift driver
  `AppHost/Sources/MelonDSNativeDriver.swift` (`RETROPLAY_HAS_MELONDS`).
- The bottom screen is the touchscreen; the RTC is set to local time on boot, reset and state load.
- Save states use melonDS `Savestate`; loading one keeps the current battery save.

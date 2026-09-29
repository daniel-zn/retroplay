# mupen64plus-next (Nintendo 64)

RetroPlay's N64 core is [mupen64plus-next](https://github.com/libretro/mupen64plus-libretro-nx)
(GPL-2.0-or-later) with the GLideN64 renderer on OpenGL ES. The exact revision, patches and build
command are in [`SOURCES.md`](SOURCES.md).

- CPU: `cached_interpreter` only (no dynarec), as iOS requires. Not paraLLEl-RDP or paraLLEl-RSP.
- The core ships as `mupen64plus.framework`: App Store Connect rejects bare `.dylib` files.

## Build

```bash
App/Vendor/fetch-core-sources.sh      # checkout + patches/mupen64plus-next-ios-headers.patch
cd ../mupen64plus-next
make platform=ios-arm64 HAVE_PARALLEL_RDP=0 HAVE_PARALLEL_RSP=0 HAVE_THR_AL=0 LLE=0
```

Then package the device (and, for development, Simulator) dylibs:

```bash
MUPEN_DEVICE_LIB=… MUPEN_SIM_LIB=… MUPEN_HEADERS=… App/Vendor/build-mupen64plus-ios.sh
```

`package-mupen64plus-framework.sh` wraps each dylib as `mupen64plus.framework` (install name,
minimum OS, Info.plist) and writes `App/Vendor/Output/mupen64plus.xcframework`. For a Simulator
build see `SOURCES.md` (`FOR_SIMULATOR=1`).

## Integration

- libretro host: `AppHost/Sources/N64/N64LibretroHost.mm`; Swift driver
  `AppHost/Sources/N64NativeDriver.swift` (`RETROPLAY_HAS_N64`).
- The host answers core options with the core's declared defaults, pinned to the cached interpreter.
- Save states use `retro_serialize`; battery saves (`SAVE_RAM`) go to `battery.srm`.

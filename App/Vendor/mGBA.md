# mGBA (Game Boy Advance)

RetroPlay's GBA core is [mGBA](https://mgba.io) ([mgba-emu/mgba](https://github.com/mgba-emu/mgba),
MPL-2.0). The exact revision is in [`SOURCES.md`](SOURCES.md).

## Build

Requires Xcode, CMake and Ninja (`brew install cmake ninja`).

```bash
App/Vendor/fetch-core-sources.sh            # checks out mgba next to this repo
RETROPLAY_ROOT="$PWD" MGBA_SRC="$PWD/../mgba" App/Vendor/build-mgba-ios.sh
```

The script configures mGBA with CMake for device and Simulator (`LIBMGBA_ONLY`, GBA core only,
`DISABLE_DEPS=ON`, static) and writes `App/Vendor/Output/mGBA.xcframework` (gitignored).

## Integration

- Swift driver: `AppHost/Sources/MGBANativeDriver.swift` (`RETROPLAY_HAS_MGBA`).
- Save states use `mCoreSaveStateNamed` / `mCoreLoadStateNamed`; the battery save is written
  through mGBA's save file under `Documents/Saves/`.
- mGBA's config is initialised with a default volume (`0x100`); without it the core mixes silence.

# RetroPlay

RetroPlay is a free, open-source emulator for iPhone with a library-first design: import the
games you own through Files, tap one, and play. RetroPlay picks the system and emulator core for
you.

| System | Core |
|---|---|
| Game Boy Advance | [mGBA](https://mgba.io) |
| Nintendo 64 | [mupen64plus-next](https://github.com/libretro/mupen64plus-libretro-nx) (GLideN64, cached interpreter) |
| Nintendo DS | [melonDS](https://melonds.kuribo64.net) |
| PlayStation Portable | [PPSSPP](https://www.ppsspp.org) (IR interpreter) |

All cores run without JIT, as iOS requires. RetroPlay includes on-screen controls modelled on
each console, game controller and keyboard support, save states with auto-resume, AirPlay, and
cover art read from the games themselves.

## No games included

RetroPlay does not include, sell, host or link to games, BIOS or firmware. Only import software
you have the right to use. Please don't open issues or pull requests containing game files.

## License

RetroPlay is free software under the **GNU General Public License v3.0 or later** (`LICENSE`,
`COPYRIGHT.md`). It is built with open-source emulator cores and libraries; their licenses and
copyright notices are in `THIRD_PARTY_NOTICES.md` and in the app under
Settings → Open Source Licenses.

The exact core revisions and RetroPlay's patches to them are recorded in
[`App/Vendor/SOURCES.md`](App/Vendor/SOURCES.md), so every release can be rebuilt from source.
Release tags (`v1.0`, …) mark the source of each version shipped.

## Building

Requirements: a Mac with Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake and
Ninja.

1. Fetch the exact core sources next to this repository and apply RetroPlay's patches:
   `App/Vendor/fetch-core-sources.sh`
2. Build the cores into `App/Vendor/Output/` with the `App/Vendor/build-*-ios.sh` scripts. Each
   core's notes are in `App/Vendor/` (`mGBA.md`, `melonDS.md`, `mupen64plus.md`, `PPSSPP.md`).
3. Generate the Xcode project with `xcodegen generate` and open `RetroPlay.xcodeproj`.

`App/` is a Swift package (`RetroPlayCore` and `RetroPlayApp`) with the tests; `AppHost/` holds the
app target and the native bridges to each core. More detail: [`SPEC.md`](SPEC.md),
[`docs/`](docs) (controls and play runtime), and [`App/Vendor/XCODE.md`](App/Vendor/XCODE.md).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

Game Boy Advance, Nintendo 64, Nintendo DS and PlayStation Portable are trademarks of their
respective owners. RetroPlay is not affiliated with or endorsed by Nintendo or Sony.

# Corresponding source for the bundled emulator cores

RetroPlay ships prebuilt emulator cores (`Output/*.xcframework`, not committed). These are
the exact upstream revisions they were built from, plus RetroPlay's local patches. Together
with this repository they are the complete corresponding source for a RetroPlay build.
`fetch-core-sources.sh` checks all of them out and applies the patches.

| Core | Upstream | Commit | License | Local changes |
|---|---|---|---|---|
| mGBA | https://github.com/mgba-emu/mgba | `aa6394c93ca24b0ff40dc9231bdb0533f415e0be` (2026-09-06) | MPL-2.0 | none |
| melonDS | https://github.com/melonDS-emu/melonDS | `906e9ebb27da8c6a715cd7abab4abfe8a8d29427` (2026-08-24) | GPL-3.0-or-later | none |
| mupen64plus-next | https://github.com/libretro/mupen64plus-libretro-nx | `f275caf4b2bfa1e6d1c51636746ea793f3d80320` (authored 2026-05-25, committed 2026-08-06) | GPL-2.0-or-later; bundled GLideN64 is GPL-2.0-only (see below) | `patches/mupen64plus-next-ios-headers.patch` |
| PPSSPP | https://github.com/hrydgard/ppsspp | `98e70c8ca3435d532a059add0b4fb90a4a091248` (2026-09-07) | GPL-2.0-or-later | none (submodules at the commits PPSSPP records, listed in `pins/ppsspp-submodules.txt`) |

The PPSSPP device build links the prebuilt FFmpeg libraries from PPSSPP's `ffmpeg` submodule
at the recorded commit. The Simulator build uses a locally rebuilt FFmpeg (`ffmpeg/ios/arm64-sim`),
which is only for development and is not part of any distributed build.

## Build commands and evidence

**mupen64plus-next (device, the build that ships).** Built from the commit above with
`patches/mupen64plus-next-ios-headers.patch` applied (two bundled headers fixed for iOS, each
marked "Modified by RetroPlay") and the Makefile unchanged:

    make platform=ios-arm64 HAVE_PARALLEL_RDP=0 HAVE_PARALLEL_RSP=0 HAVE_THR_AL=0 LLE=0

This produces `mupen64plus_next_libretro_ios.dylib`, which `package-mupen64plus-framework.sh`
wraps as `mupen64plus.framework`. The shipped device binary was rebuilt this way from
`fetch-core-sources.sh` output on 2026-09-29 (Xcode 27, iPhoneOS 27.0 SDK) so that it corresponds
to this source exactly.

**mupen64plus-next (Simulator, development only, never distributed).** The Simulator slice
is an older development build that uses the angrylion software renderer (GLideN64's GLES path
doesn't run in the Simulator). `patches/mupen64plus-next-ios-simulator.patch` retargets the
`ios-arm64` Makefile branch at the Simulator; `FOR_SIMULATOR=1 ./fetch-core-sources.sh` applies it,
then build with `IOSSDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"`.

**mGBA.** `build-mgba-ios.sh` (CMake: `LIBMGBA_ONLY`, `DISABLE_DEPS=ON`, GBA core only). The
library reports version `0.11-1-aa6394c`, matching the commit above.

**melonDS.** `build-melonds-ios.sh` (JIT, OpenGL and Qt off), from an unmodified checkout at
the commit above.

**PPSSPP.** `build-ppsspp-ios.sh` with submodules at the commits PPSSPP records. The core
reports `v1.20.4-1645-g98e70c8ca3` at boot (no `-dirty` suffix). FFmpeg is PPSSPP's prebuilt
LGPL-2.1-or-later build from the `ffmpeg` submodule, whose repository also holds the FFmpeg
source and the iOS build script; because the whole app's source is published, users can
rebuild and relink it as the LGPL requires.

## Known licensing issue: GLideN64

GLideN64 (the N64 renderer inside mupen64plus-next) is licensed "GNU General Public License
version 2", without "or later", and itself includes xBRZ (GPL-3.0 with a MAME exception). A
GPL-2.0-only component is technically incompatible with GPL-3.0 code such as melonDS in one
binary. This is accepted as a known risk (the same combination ships in other open-source iOS
emulators); see `docs/licensing/summary.md`.

The N64 core is packaged as `mupen64plus.framework` by `package-mupen64plus-framework.sh`
(install name, minimum OS and Info.plist only; the machine code is unchanged).

When a core is rebuilt from a different revision, update this table in the same commit, and
tag the RetroPlay release so the source for every shipped version stays identifiable.

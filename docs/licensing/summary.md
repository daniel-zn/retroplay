# RetroPlay: open-source license inventory (2026-09-29)

Files in this folder:
- `inventory.json`: 88 entries, 56 of which need their notice text shipped. It merges the per-core files `inventory-ppsspp.json`, `inventory-mupen64plus.json` and the mGBA/melonDS/font entries.
- `notes-ppsspp.md` and `notes-mupen64plus.md`: detailed evidence for those two cores.
- License texts, named `<component>-<SPDX>.txt`. These are exact copies of the files in each checkout. Where a component has no license file, the text is its source-header comment copied verbatim; the inventory says so for each one.

Top-level license texts:

| License | File |
|---|---|
| GPL-3.0 | `melonDS-GPL-3.0-or-later.txt` |
| GPL-2.0 | `ppsspp-GPL-2.0-or-later.txt` (PPSSPP `LICENSE.TXT`, which also carries the PSPSDK BSD-3 notice) and `mupen64plus-next-GPL-2.0-or-later.txt` |
| MPL-2.0 | `mgba-MPL-2.0.txt` |
| LGPL-2.1 | `ffmpeg-LGPL-2.1-or-later.txt` and `blip_buf-LGPL-2.1-or-later.txt` |
| OFL-1.1 | `PressStart2P-OFL-1.1.txt` |

## Per core: what is actually in the binaries

### mGBA
Build: `libmgba.a`, verified to be the aa6394c build (`strings`: `0.11-1-aa6394c`). CMake options were `LIBMGBA_ONLY`, `DISABLE_DEPS=ON`, GBA core only, no scripting or debuggers.

Linked:
- mGBA itself (MPL-2.0)
- inih (BSD-3-Clause, notice required)
- Public-domain pieces: MurmurHash3, Gary Brown CRC32, and MD5/SHA-1 derived from Unlicense and public-domain sources

Not linked: zlib, libpng, LZMA, SQLite, discord-rpc and Lua. There are no `png_`, `inflate` or `sqlite` symbols in the library.

The build ran from `~/src/mgba`, which no longer exists. The embedded git hash still matches aa6394c.

### melonDS
Build: `libmelonDS.a`, which is byte-identical to `melonDS-libs/device`. CMake options were JIT off, OpenGL off and Qt off.

Linked:
- melonDS (GPL-3.0-or-later), including DSP_HLE
- FreeBIOS by Gilead Kutnick (BSD-2-Clause, notice required)
- blip_buf (LGPL-2.1-or-later)
- FatFs R0.14b (no notice needed in binary form)
- Teakra (MIT)
- tiny-AES-c (Unlicense)
- Steve Reid SHA-1 (public domain)
- xxHash 0.8.3 (BSD-2-Clause)

Not linked: the Dolphin emitter code, network code and the frontend.

The binary carries no embedded git hash, so I could not confirm from the binary that the build used 906e9eb. The build dates (Sep 8) come after that commit (Aug 24).

### mupen64plus-next
Build: `mupen64plus.framework` (a dylib). Its code is identical to `out-ios/mupen64plus_next_libretro_ios.dylib`.
- Included: cached interpreter, GLideN64 on GLES, rsp-hle.
- Not included: dynarec, paraLLEl, angrylion, cxd4.
- Uses its own bundled copies of zlib 1.2.8, libpng 1.6.34 and minizip.
- The exact `make` command is not recorded anywhere; it was inferred.

See `notes-mupen64plus.md` for detail.

### PPSSPP
Build: `libPPSSPP.a` merges all 39 CMake static libraries plus 6 prebuilt FFmpeg libraries. The inventory lists 43 linked components (glslang, SPIRV-Cross, libzip, libpng17, Lua, zstd, snappy, libchdr, rcheevos, basis_universal, imgui, armips, and others).

Not linked: zlib (it comes from the iOS system `libz`) and discord-rpc (even though `USE_DISCORD=ON`).

**FFmpeg is LGPL-only.** The strings in the shipped library read `lib* license: LGPL version 2.1 or later`, and there are 0 hits for `--enable-gpl`, `--enable-nonfree` or `--enable-version3`. It is upstream's old prebuilt FFmpeg (version 537ef3b0e3, the 3.0.x line, built with the iPhoneOS 10.2 SDK). Because it is linked statically, the LGPL requires that users be able to relink it: ship the source plus build scripts, or the object files.

### App resources
- **Press Start 2P** (OFL-1.1). The SHA-256 matches `SOURCE.md`. The OFL and FONTLOG files are bundled.
- **PPSSPP assets.** All are byte-identical to ppsspp@98e70c8ca3. Provenance is in `notes-ppsspp.md`.

## Red flags

1. **GPL-2.0-only code is combined with GPL-3.0 code.**
   - GLideN64's `LICENSE` says "GNU General Public License version 2", with no "or later".
   - GPL-3 code is linked in two places:
     - Inside GLideN64: xBRZ (`GLideNHQ/TextureFilters_xbrz.cpp`; 13 xbrz symbols are in the shipped binary).
     - In the rest of the app: melonDS (GPL-3.0-or-later), and in PPSSPP libkirk (GPL-3.0-or-later), xBRZ and aemu_postoffice.
   - `retroplay/COPYRIGHT.md` claims the whole build is GPL-3.0-or-later. That claim can't hold while GLideN64 is GPL-2.0-only.
   - GLideN64 also says it contains fragments of gles2n64, which is LGPL-3.0. I could not confirm which files hold them.
2. **GPL and the App Store.** Apple's usage rules are widely treated as "further restrictions" under the GPL (the VLC/FSF precedent). This needs a legal or business decision; a notices file does not fix it.
3. **Sony PSP keys are compiled in** (libkirk key vault, `Core/ELF/PrxDecrypter.cpp`).
4. **flash0 PGF fonts have no license statement anywhere in the PPSSPP repo.**
   - History: they started as "JPCSP's free font files" (`1429d0206a`, 2013). nassau-tk regenerated them in 2020–23 (#13510 and others).
   - `dc34bea8d4` (2021-01-20) is titled "camouflage the Font name". Before it, the embedded names were Source Han Sans (OFL-1.1, whose notice must accompany it) and Ume Gothic/Mincho. After it, they carry Sony/Fontworks names ("FTT-NewRodin Pro", "FTT-Matisse Pro Latin").
   - The current glyph sources are inferred from those names, not confirmed.
5. **`ppge_atlas.zim` was rendered from proprietary fonts**: Kozuka Gothic Pro and Arial Unicode MS, per `ppge_atlasscript.txt`. Glyphs were last regenerated in `6ef779402a` (2016).
6. **Missing license texts in the checkouts:**
   - imgui has no `LICENSE.txt`; the full MIT text must come from upstream v1.91.6.
   - sfmt19937 refers to a `LICENSE.txt` that isn't present.
   - libkirk's `amctrl.c` and `ec.c` have no license statement at all.
7. **Complete-source obligations for mupen64plus:**
   - The device `make` command is not recorded anywhere.
   - `SOURCES.md` says the patch's Makefile hunk applies, but the device build did not use it.
   - The libpng `pngpriv.h` edit has no "modified" marking, which both the libpng and zlib licenses require.
   - `SOURCES.md` gives the commit date as 2026-08-06, but git shows 2026-05-25.
8. **Build provenance.** mGBA and PPSSPP were built from `~/src/*` checkouts that no longer exist. PPSSPP's `build-ios-device` references `~/src/ppsspp`, so its exact source state could not be verified beyond the asset matches.

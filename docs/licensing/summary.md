# RetroPlay: open-source license inventory (2026-09-29)

Files in this folder:
- `inventory.json`: 133 entries, 88 of which need their notice text shipped. It merges the per-core files `inventory-ppsspp.json`, `inventory-mupen64plus.json`, the mGBA/melonDS/font entries and (added 2026-10-12) the five libretro cores below.
- `notes-ppsspp.md` and `notes-mupen64plus.md`: detailed evidence for those two cores.
- License texts, named `<component>-<SPDX>.txt`. These are exact copies of the files in each checkout. Where a component has no license file, the text is its source-header comment copied verbatim; the inventory says so for each one.

Top-level license texts:

| License | File |
|---|---|
| GPL-3.0 | `melonDS-GPL-3.0-or-later.txt` |
| GPL-2.0 | `ppsspp-GPL-2.0-or-later.txt` (PPSSPP `LICENSE.TXT`, which also carries the PSPSDK BSD-3 notice) and `mupen64plus-next-GPL-2.0-or-later.txt` |
| MPL-2.0 | `mgba-MPL-2.0.txt` |
| LGPL-2.1 | `ffmpeg-LGPL-2.1-or-later.txt` and `blip_buf-LGPL-2.1-or-later.txt` |
| OFL-1.1 | `VT323-OFL-1.1.txt` |

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

### Libretro cores (added 2026-10-12)
Built by `App/Vendor/build-libretro-cores-ios.sh` from unmodified checkouts (commits in `App/Vendor/SOURCES.md`). "Compiled" below means the files a `clang -M` dependency scan reports for every compile command of `make -n` with the script's exact flags; no binary symbol check was done (the cores were not rebuilt for this inventory).

**Nestopia UE** (GPL-2.0-or-later; headers say "version 2 of the License, or (at your option) any later version").
- Linked: Nestopia core + NstDatabase.xml (embedded), nes_ntsc 0.2.2 (LGPL-2.1-or-later, Shay Green), NstSha1 (Steve Reid public domain), libretro-common (MIT).
- Not linked: zlib (`-DNST_NO_ZLIB`).
- `libretro/nesfont.h` (8x8 font for the NSF player) has no origin or notice; treated as part of Nestopia.

**bsnes** (GPL-3.0-only: `LICENSE.txt` says "specifically version 3 of the License and no other version").
- Linked: bsnes, libco and nall (ISC, byuu), SameBoy (MIT, Lior Halphon), snes_spc S-DSP and snes_ntsc (LGPL-2.1-or-later, Shay Green), LZMA SDK 19.00 (public domain), S-DD1 decompressor (Andreas Naive, public domain), libretro.h (MIT).
- DSP-4 emulator code (`sfc/coprocessor/dsp4/dsp4emu.c`, "Copyright (c) 2004-2006 Dreamer Nom, John Weidman, Kris Bleakley, Nach, z80 gaiden") has no license statement; see red flag 9.
- `filter/` (2xSaI, Super Eagle, hq2x/lq2x, scale2x) and `nall/decode/inflate.hpp` ("a bad implementation of inflate from zlib/minizip") have no third-party notices; recorded as part of bsnes/nall.
- Not compiled: ruby, hiro, target-bsnes, `bsnes/gb` outside `Core/`.

**ProSystem** (GPL-2.0-or-later; every core file: "either version 2 of the License, or (at your option) any later version").
- Linked: ProSystem, TiaSound and PokeySound (Ron Fries, LGPL-2.0-only "Library GPL version 2"; s.3 allows conversion to GPL), BupBoop/CoreTone (Zlib), libretro-common (MIT).
- The LGPL-2.0 full text is not in the checkout; the shipped copy comes from `pcsx_rearmed/deps/lightrec/COPYING`.

**clownmdemu** (AGPL-3.0-or-later: README "AGPLv3 (or any later version)"; clown68000 headers say the same).
- Linked (one `unity.c` translation unit): clownmdemu core, libretro frontend + frontend-common, clown68000, clownz80 (README says only "AGPLv3"; recorded as AGPL-3.0-only), ClownCD, clownresampler, clowncommon (0BSD), libchdr (BSD-3-Clause), LZMA SDK 25.01 (public domain), miniz 3.1.1 (MIT), zstd 1.5.7 decoder (BSD-3-Clause chosen), dr_flac / dr_wav (Unlicense OR MIT-0), dr_mp3 (same, plus minimp3 CC0-1.0), stb_vorbis 1.22 (MIT OR Unlicense), libretro-common headers (MIT).
- Nested submodule commits are pinned in `App/Vendor/pins/clownmdemu-libretro-submodules.txt`.

**PCSX-ReARMed** (GPL-2.0-or-later; headers "either version 2 ... or (at your option) any later version" or "GNU GPLv2 or later").
- Build: `Makefile.libretro`, `DYNAREC=0` (`-DDRC_DISABLE`), `BUILTIN_GPU=neon`, `HAVE_CHD`, `USE_MINIZ`.
- Linked: libpcsxcore, libretro frontend, P.E.Op.S. SPU (Pete Bernert), psx_gpu NEON renderer (Exophase) and gpulib (notaz; GPL-2.0-or-later or LGPL-2.1-or-later), GTE divider from MAME (BSD-3-Clause, smf), Shift-JIS BIOS font (Shinonome k14goth, public domain), libchdr (BSD-3-Clause), LZMA SDK 26.02 incl. arm64 asm (public domain), miniz 3.1.2 (MIT), zstd 1.5.7 decoder (BSD-3-Clause), dr_flac (Unlicense OR MIT-0), libretro-common (MIT).
- Not linked: lightrec/GNU lightning (only two declaration-only headers are included), new_dynarec (only `emu_if.c` with `DRC_DISABLE`), libpicofe, zlib (link line is `-lpthread -lm -ldl`).
- `gte_divider.c` says only "Licensed under the BSD-3-Clause"; the shipped text is the SPDX BSD-3-Clause template with smf's copyright line.

**Compatibility.** Every new license combines with GPL-3.0: the GPL-2.0-or-later and LGPL cores upgrade to v3, bsnes is GPL-3.0 itself, and GPLv3 s.13 explicitly allows linking with AGPLv3 code (clownmdemu). The AGPL's extra s.13 duty (offer source to users who interact over a network) does not apply to an offline emulator, and the app already publishes its complete source. Nothing is non-commercial. See red flags 9-11.

### App resources
- **VT323** (OFL-1.1). The SHA-256 matches `VT323-SOURCE.md`. The OFL file is bundled.
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
9. **bsnes DSP-4 code has no license statement.** `dsp4emu.c` names its authors (Dreamer Nom, John Weidman, Kris Bleakley, Nach, z80 gaiden) but no license. It came from the ZSNES/Snes9x DSP-4 work and has shipped in bsnes/higan under the GPL for years; I could not confirm a grant from those authors. The inventory records it as `LicenseRef-NoLicenseStatement`.
10. **More GPL-3.0-only code next to GPL-2.0-only GLideN64.** bsnes is GPL-3.0-only, the same conflict as red flag 1. It also means the combined app can only be distributed under GPL-3.0 (not "or later"), whatever `COPYRIGHT.md` says.
11. **AGPL-3.0 (clownmdemu) in an App Store app.** It is legally compatible with GPL-3.0, but the same App Store "further restrictions" question as red flag 2 applies, and AGPL authors may be stricter about it.

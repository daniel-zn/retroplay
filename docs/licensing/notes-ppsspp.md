# PPSSPP in RetroPlay: license notes

Checkout: `ppsspp` @ `98e70c8ca3`. Shipped lib: `retroplay/App/Vendor/Output/PPSSPP.xcframework/ios-arm64/libPPSSPP.a` (57 MB, 1326 members, built Sep 7).
Inventory: `inventory-ppsspp.json` (43 linked components, plus 9 entries marked "not linked").

## How libPPSSPP.a was assembled (reconstructed)
- No merge script exists. `retroplay/App/Vendor/build-ppsspp-ios.sh` is a stub. It only runs `xcodebuild -create-xcframework`.
- Reconstruction: I compared `ar -t` member names against every archive in `build-ios-device/lib/Release/*.a`, `build-ios-device/build/*/Release-iphoneos/*.a` and the arm64 slice of `ffmpeg/ios/universal/lib/*.a`. Each of those archives is fully present (100%), apart from a few duplicate basenames (for example 387/388 libCore and 158/160 libavcodec). So the merged lib = all 39 CMake static libs + the 6 prebuilt ffmpeg libs.
- CMakeCache options that matter: `USE_FFMPEG=ON`, `USE_SYSTEM_FFMPEG=OFF`, `USE_DISCORD=ON` (no Discord code actually got in), `USE_MINIUPNPC=ON`, `USE_SYSTEM_LIBPNG=ON` (the in-tree libpng17 was still built and merged), `ARMIPS_LIBRARY_ONLY=ON`.
- zlib is NOT inside the lib. `inflate*`, `deflate*` and `crc32` are undefined (`U`) symbols, so they resolve against the iOS SDK libz. No zlib notice is needed for PPSSPP (Apple system library).

## FFmpeg: LGPL-only (confirmed)
- Evidence from `strings` on the shipped libPPSSPP.a:
  - `libavcodec|libavformat|libavutil|libswresample|libswscale|libavdevice license: LGPL version 2.1 or later`
  - `FFmpeg version 537ef3b0e3`, `Lavc57.24.102`, `Lavf57.25.100` (FFmpeg 3.0 era; the `RELEASE` file says 3.0.2).
  - The embedded configure line has no `--enable-gpl`, `--enable-nonfree` or `--enable-version3` (0 hits). The line is: `--prefix=ios/arm64 --enable-cross-compile --arch=aarch64 ... --sysroot=.../iPhoneOS10.2.sdk ... --disable-everything --disable-shared --enable-static --disable-iconv --disable-videotoolbox --disable-vda --enable-zlib --disable-lzma --disable-bzlib --disable-filters --disable-programs --disable-network --disable-avfilter --disable-postproc --disable-encoders ... --enable-decoder=h263,h263p,h264,mpeg2video,aac,atrac3,atrac3p,mp3,pcm_s16le,pcm_s8 --enable-encoder=ffv1,mpeg4,pcm_s16le --enable-demuxer=... --enable-muxer=avi --enable-parser=... --enable-protocol=file ... --enable-pic`
  - This matches `ffmpeg/shared_options.sh` + `ffmpeg/ios-build.sh`.
- These are upstream's prebuilt binaries: ffmpeg submodule `b87f7c6d52`, built with the iPhoneOS 10.2 SDK. They were not rebuilt locally. The submodule's working-tree `ffmpeg/config.h` comes from a later local `ios/arm64-sim` build and also shows `CONFIG_GPL 0`, `CONFIG_NONFREE 0`.
- The linked libs are avcodec, avformat, avutil, swresample, swscale and **avdevice** (only `alldevices.o`, `avdevice.o` and one other member).
- `ext/at3_standalone` is also LGPL-2.1-or-later. It is FFmpeg's ATRAC3/3+ code extracted by PPSSPP.
- Obligation: static LGPL linking in an iOS app requires relink capability, meaning you offer the object files or the complete source plus build scripts (LGPL-2.1 §6). Ship `ffmpeg-LGPL-2.1-or-later.txt` + `ffmpeg-LICENSE-md.txt`.

## Effective license of the combined binary: GPL-3.0 (red flag)
- PPSSPP core is GPL-2.0-or-later (LICENSE.TXT). LICENSE.TXT also carries the PSPSDK BSD-3 notice, which must be reproduced.
- Linked GPL-3 parts:
  - `ext/libkirk/kirk_engine.c`: GPL-3.0-or-later.
  - `ext/xbrz`: GNU GPL with no version given in the header, with a MAME exception; upstream xBRZ is GPL-3.0.
  - `ext/aemu_postoffice`: the repo ships `gpl-3.0.txt`; there are no file headers and no "or later" statement (unconfirmed).
- Together these make the distributed binary GPL-3.0 as a whole. GPL-3 plus App Store terms is the well-known FSF/VLC conflict: Apple's usage rules count as "further restrictions". This is a legal-judgment item, not settled here.
- libkirk and `Core/ELF/PrxDecrypter.cpp` embed Sony PSP crypto keys (the KIRK key vault and PRX tag keys, "Thank you PSARDUMPER & JPCSP keys"). That is a potential IP/DMCA/App Review risk.

## Missing or incomplete license texts in the checkout
- `ext/imgui`: no LICENSE.txt. The header just says "standard MIT License". The full MIT text must come from upstream ocornut/imgui v1.91.6 (not in checkout).
- `ext/sfmt19937`: the header says "see LICENSE.txt", but that file is absent. Only the header comment was extracted.
- `ext/libzip`, `ext/libpng17`, `ext/lua`, `ext/pugixml`, `ext/vma`, `ext/basis_universal`, `ext/xbrz`, `ext/libkirk`, `ext/at3_standalone`, `ext/xxhash.h`, `riscv-disas`, `loongarch-disasm`, `disarm`, `gl3stub`, `tinyformat`, `dr_flac`, `stb`, `minimp3`: these have no license file. I extracted the header comment verbatim with `sed -n` (line ranges are reproducible from the source files).
- `ext/libkirk/amctrl.c` ("written by tpu") and `ec.c`: no license statement at all.
- xBRZ and aemu_postoffice need a GPL-3.0 full text. The `aemu_postoffice-GPL-3.0.txt` copy serves for both.

## App-bundled PPSSPP assets (from `retroplay/AppHost/Supporting/assets`, copied via project.yml `AppHost/Supporting/assets`)
I checked every file against the checkout. All are byte-identical to `ppsspp/assets/*` at 98e70c8ca3 (`cmp`/`diff -rq`).

| Asset | Provenance / license statement found |
|---|---|
| `ppge_atlas.zim/.meta` | Generated by PPSSPP atlastool from `ppge_atlasscript.txt`. That script rasterizes **`C:/Windows/Fonts/KozGoPro-Medium.otf` (Adobe Kozuka Gothic Pro)** and **`C:/Windows/Fonts/ARIALUNI.ttf` (Arial Unicode MS)**, plus `source_assets/image/{cross,circle,square,triangle}.png`. The glyphs were last regenerated at `6ef779402a` (2016-02-15, "Update PPGE atlas"). `372deeaef1` (2021) only recompressed with zstd. Later script edits (2025, Nab) do not appear to have been re-rendered: the zim hasn't changed since 2021. That's an inference and is unconfirmed. The atlas holds bitmaps derived from proprietary fonts, and no license statement for them exists. **Red flag (gray area).** |
| `flash0/font/*.pgf` (18 files) | See below. **Red flag.** |
| `vfpu/*.dat` (15) | Lookup tables added by fp64 in `67bb17eba3` (2023-03-09, "Add more vfpu_*, move tables to assets"). No separate license, so PPSSPP GPL-2.0-or-later is presumed. The generation method isn't documented in the commit (unconfirmed whether measured from hardware). |
| `compat.ini`, `langregion.ini` | PPSSPP-authored data, GPL-2.0-or-later presumed. |
| `knownfuncs.ini` | Function hashes → names. Created `8c5fb2b3f3` / `2c57a0a897` (2013, Unknown W. Brackets / Henrik Rydgard). PPSSPP-authored. |

### flash0 PGF fonts: exact repo record
- The repo has no README, license file, history.md entry or doc stating the origin or license of the PGF fonts. `history.md:571` only says "Numerous fixes to the builtin fonts by nassau-tk".
- History (`git log -- assets/flash0/font flash0/font`):
  - `1429d0206a` 2013-02-27 Henrik Rydgard, "Add JPCSP's free font files." The embedded PGF names at that point were Sazanami Gothic (jpn0), UnDotum (kr0), Liberation Sans/Serif (ltn*).
  - `3967bf8cf5` 2013-08-12 w.ms "Update JPN0.PGF" / `0436b751a7` (the file name was then "Microsoft YaHei", a proprietary font, as of `8d1ece05ca` 2017). Later replaced.
  - `77c1e96588` 2020-10-09 "Change jpn0.pgf for a new one generated by nassau-tk" (#13510). The name was "Ume Gothic S5".
  - `f68e0fecd4`, `3831d2346d`, `41ee5fbd93`, `06b0e33839`, `737e0d55d4`, `b5e2300770` (2020, nassau-tk): all ltn fonts were rebuilt. `75bdb5ff17` switched kr0.
  - **`dc34bea8d4` 2021-01-20 nassau-tk, "PGF Fixed Bold & Italic property and camouflage the Font name."** Before this commit the embedded names were: jpn0/kr0 = **"Source Han Sans"**; ltn0/2/4/…/14 = **"Ume Hy Gothic"**; ltn1/3/…/15 = **"Ume P Mincho"**. After it, the names were changed to Sony firmware names: `FTT-NewRodin Pro DB`, `FTT-NewRodin Pro Latin`, `FTT-Matisse Pro Latin`, `AsiaKNHH-SONY-uni`.
  - Last commits per file: jpn0 `e4aa9e517f` (2023-01-29), kr0 `dc34bea8d4`, ltn0/ltn4 `a384b62247`, ltn2/ltn6 `848142d2ac`, ltn1/3/5/7 `5742f2f389`, ltn8–15 `da40ed6e81`. All by nassau-tk.
- Inference, unconfirmed: the current glyphs derive from Source Han Sans (SIL OFL-1.1, Adobe, Reserved Font Name "Source") and the Ume fonts (Ume font license, permissive). **Red flags:**
  1. OFL-1.1 requires the copyright notice and the OFL to accompany modified versions. Nothing in the repo does this.
  2. The fonts now carry trademarked Fontworks/Sony font names (FTT-NewRodin, FTT-Matisse), and a commit message says "camouflage".
  3. No provenance statement exists in the repo.
- Recommendation: get nassau-tk's source statement (PPSSPP issues #13510, #13190, #13588, #13721), or ship the OFL + Source Han Sans copyright + Ume license as a precaution.

## Other notes
- `USE_DISCORD=ON`, but discord-rpc is not linked. naett, FreeType, OpenXR-SDK, libadrenotools, ext/sha1, ext/zlib and MoltenVK are also not linked.
- `Core/RetroAchievements.cpp` is (GPL-2.0 OR GPL-3.0 OR CC-BY-NC-ND-4.0) from DuckStation. The GPL option is chosen.
- `ffmpeg-LICENSE-md.txt` is FFmpeg's LICENSE.md. It's shipped alongside the LGPL text, not as a separate license.
- The glslang LICENSE.txt bundles BSD-3/BSD-2/MIT/Apache-2.0 plus the GPL-3-with-Bison-exception text for glslang_tab.cpp. Ship the whole file.

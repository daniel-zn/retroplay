# mupen64plus-next (RetroPlay N64 core): license notes

Checkout: `mupen64plus-next` @ `f275caf` plus 3 local diffs, byte-identical to `retroplay/App/Vendor/patches/mupen64plus-next-ios.patch`.
Shipped binary: `retroplay/App/Vendor/Output/mupen64plus.xcframework/ios-arm64/mupen64plus.framework/mupen64plus`.
Inventory: `inventory-mupen64plus.json` (19 components).

## Which build shipped (facts)

- The shipped device binary's `__TEXT` disassembly matches `out-ios/mupen64plus_next_libretro_ios.dylib` exactly (built 2026-09-08 10:03). The only differences are the ones the packaging script makes: `vtool` minos 26.0 and the install name.
- That dylib has `LC_VERSION_MIN_IPHONEOS 8.0`, so it came from the **unmodified** `ios-arm64` Makefile branch. The Makefile diff to `-mios-simulator-version-min=18.0` has mtime 10:55, which is after that build.
- `pngpriv.h` (10:01:37) and `zutil.h` (10:02:51) were edited before the 10:03 build. The header fixes are therefore in the shipped binary (inferred from timestamps).
- The `.o` tree in the checkout is a **later simulator build** (platform 7, minos 18.0), and it includes angrylion and cxd4. I used it only to match symbols. It is not the device build.
- In `ios-arm64`, the Makefile defaults are `HAVE_PARALLEL_RDP=1 HAVE_PARALLEL_RSP=1 HAVE_THR_AL=1 LLE=1`. The shipped binary has none of them: 0 of 168 angrylion symbols, and cxd4 `rsp.o` matches only 4 of 127 symbols. Those 4 are `CFC2/MTC2`-style names that `pure_interp.o` also defines. There are no paraLLEl or Vulkan symbols and no `new_dynarec` symbols. That leaves 274 `cached_interp` symbols, GLideN64 on GLES (links OpenGLES.framework and AudioToolbox only), and rsp-hle.
- **Inferred invocation (unconfirmed, no shell history):** `make platform=ios-arm64 HAVE_PARALLEL_RDP=0 HAVE_PARALLEL_RSP=0 HAVE_THR_AL=0 LLE=0` (dynarec is already off because `WITH_DYNAREC=` is empty).
- Bundled `SYSTEM_*=0` copies are compiled in: zlib 1.2.8, libpng 1.6.34, minizip, and xxHash (header-only). md5 is always built.
- Not compiled: FreeType (headers only in `GLideN64/src/inc`, no `FT_` symbols), the Glow/Bloom shader (no code in the compiled sources), OGLFT/OSD, the Bitstream font, `GLideNHQ/lib/*.a` (libdxtn/libpng/libz prebuilts are not linked), GLideNUI, paraLLEl-RDP/RSP, lightning, angrylion, and cxd4.
- `GraphicBuffer/PrivateApi/GraphicBuffer.cpp` (**GPL-3.0-or-later**, "Imagine" project) is in `SOURCES_CXX`, but on iOS it compiles to an empty object (0 defined symbols), so no code from it ships.
- The **simulator slice** of the XCFramework *does* contain angrylion (`_angrylionDrawScreen` etc.). It is dev-only and not in the device IPA. If it is ever distributed, audit angrylion's license separately.

## Local modifications (source obligations)

1. `custom/dependencies/libzlib/zutil.h`: under `__APPLE__`, the `#define fdopen(fd,mode) NULL` fallback is suppressed, marked with the comment `RETROPLAY_IOS_FDOPEN_FIX`. **The zlib license says "Altered source versions must be plainly marked as such."** The in-line comment plus the published patch should be enough. It would be safer still to add a note that zutil.h was modified by RetroPlay (date and reason).
2. `custom/dependencies/libpng/pngpriv.h`: the `<fp.h>` include branch for `TARGET_OS_MAC` now excludes `TARGET_OS_IPHONE`/`TARGET_OS_SIMULATOR`. The libpng license (1.6.34, SPDX `Libpng`) also says **altered versions must be plainly marked** and must not be misrepresented as the original. This edit has **no marking comment**. Add one to the patch, for example `/* Modified for RetroPlay iOS build, 2026-09-08 */`.
3. `Makefile`: the `ios-arm64` branch is switched to simulator min-version flags. This was not used for the device binary. GPL-2.0 §2(a) requires modified files to carry prominent change notices, and §3 requires "the scripts used to control compilation". The exact device `make` command **is not recorded anywhere**. Record it in `SOURCES.md`, and note that the Makefile part of the patch is for simulator builds only.

## Red flags / open questions

- **xBRZ (GPL-3.0) inside GLideN64, whose licence is "GPL version 2" with no "or later".** `GLideNHQ/TextureFilters_xbrz.cpp` is compiled and its symbols are in the shipped binary (`xbrz::ScalerCfg`, `scaleImage<Scaler2x..4x>`). The header grants "GNU General Public License: …/gpl-3.0" with a MAME-only linking exception. GPL-3.0 and GPL-2.0-only code cannot lawfully be combined. Most GLideN64 files have no per-file header, so the project-level "version 2" statement governs (GPL-2.0-only). This is a known upstream incompatibility. The cleanest fix is to drop `TextureFilters_xbrz.cpp` and stub the xBRZ filter options, then rebuild.
- **gles2n64 fragments (LGPL-3.0).** `GLideN64/licenses/gles2n64/LICENSE` is LGPLv3 text, and `GLideN64/LICENSE` says GLideN64 "contains source code fragments of glN64 ported to Android by yongzh". I could not identify which compiled files hold those fragments (none carry a gles2n64 header). LGPL-3.0 is not GPL-2.0-only compatible either. **Unconfirmed** (the fragments may be trivial or rewritten), but it is the same class of problem as xBRZ.
- **GPL and the App Store.** All three main parts are GPL-2 (core/rsp-hle GPL-2.0-or-later, GLideN64 GPL-2.0-only). The App Store terms (usage rules, DRM) are widely considered "further restrictions" under GPLv2 §6 (the VLC/FSF 2010–2011 precedent). This is a legal/business decision for the maintainers, not a notice-file issue. At minimum, ship the GPL text, credits, and a working complete-source offer: the upstream commit, the patch, and the exact build command and scripts.
- `SOURCES.md` gives the commit date as 2026-08-06, but `git log` author date is 2026-05-25. Minor; check which one is intended.
- **Hacktarux / Mupen64 0.5 lineage:** GPL-licensed per `mupen64plus-core/LICENSES`. No non-free code was found. `winlnxdefs.h` (Hacktarux) is GPL-2.0-or-later.
- **N64 CIC-NUS-6105 (X-Scale):** BSD-2-Clause-Views. It is GPL-compatible, but the binary must reproduce its notice.
- **PPSSPP deposterize** snippet in `GLideNHQ/TextureFilters.cpp` ("Copyright (c) 2012- PPSSPP Project") has no licence text in the file. PPSSPP is GPL-2.0-or-later, so it is compatible (assumed).
- **Notice texts that must appear in the app** (BSD/MIT family): GLSL-FXAA (MIT), webgl-meincraft FXAA (BSD-3-Clause), readerwriterqueue (BSD-2-Clause), both xxHash copies (BSD-2-Clause), libretro-common/libretro.h (MIT), CIC-6105 (BSD-2-Clause-Views). Zlib, Libpng, minizip, md5 and Preshing (all zlib-style) do not require a binary notice, but including them is recommended.
- `libco` aarch64 is marked "public domain". No notice is needed.

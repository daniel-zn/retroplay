# PPGe atlas

Vendored from the sibling PPSSPP checkout (`assets/ppge_atlas.zim` and `assets/ppge_atlas.meta`) so PSP `sceUtility` dialogs can draw text and button icons.

- Upstream: https://github.com/hrydgard/ppsspp (GPL-2.0)
- `ppge_atlas.zim` SHA-256: `3ab7fcf6956d0281ada94d501fc6d1cfa8fc034f139e25fed6c829f723d92a95`
- `ppge_atlas.meta` SHA-256: `2eadb18c05d8f492b46c23bcbad4f4811c98cf717145536ccfe136787845f2ed`

RetroPlay bundles these files and does not download them. They are PPSSPP's UI atlas, not a game ROM or save.

# PPSSPP runtime data

Also vendored from the same PPSSPP checkout (commit `98e70c8ca3`, matching the prebuilt `PPSSPP.xcframework`), read by the core through its asset VFS:

- `vfpu/*.dat` — VFPU math lookup tables (`Core/MIPS/MIPSVFPUUtils.cpp`). Without them VFPU sin/cos/sqrt/etc. return wrong values and games can hang or render incorrectly.
- `compat.ini` — per-game compatibility settings (`Core/Compatibility.cpp`).
- `langregion.ini`, `knownfuncs.ini` — language/region defaults and known-function hashes.

None of these are game ROMs, saves or firmware dumps.

PPSSPP's replacement PSP system fonts (`assets/flash0/font/*.pgf`) are deliberately **not**
bundled: the PPSSPP repository records no license for them and their embedded font names were
changed upstream ("camouflage the Font name", dc34bea8d4), so their origin can't be verified.
Without them PPSSPP extracts the real fonts from the firmware updater on the user's own game
disc (`InstallFontsFromDiscUpdater` in `Core/HLE/sceFont.cpp`), which most retail UMDs carry.


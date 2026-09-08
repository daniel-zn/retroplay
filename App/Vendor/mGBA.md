# mGBA for RetroPlay (M1) — home Mac one-shot

RetroPlay’s GBA core is **[mGBA](https://mgba.io/)** ([mgba-emu/mgba](https://github.com/mgba-emu/mgba), **MPL 2.0**).

Agents do **not** build this on Linux and do **not** ask anyone else to build it for you. When you are at a Mac (miniMac or MacBook), run the steps below once.

This repo does **not** contain a prebuilt XCFramework or the mGBA source tree.

**Mac mini status (2026-09-08):** XCFramework built locally at
`/Users/danielsmacmini/src/retroplay/App/Vendor/Output/mGBA.xcframework` (ios-arm64 + sim). Product bot does not copy it into git.

---

## Checklist — ready for home Mac build

Repo state (already on `main`):

- [x] `App/Vendor/build-mgba-ios.sh` — CMake device + simulator → `mGBA.xcframework`
- [x] `App/Vendor/Bridging/RetroPlay-Bridging-Header.h` — C headers for the app target
- [x] `App/Vendor/Bridging/README.md` + `App/Vendor/XCODE.md` — drop-in / flags
- [x] `MGBACore` + `CoreFactory` + `RETROPLAY_HAS_MGBA` compile flag
- [x] Play UI, GBA pad, run-loop, frame bitmap, save paths, unit tests
- [x] `App/Vendor/Output/` gitignored (local XCFramework stays on your machine unless you choose to commit it)

Your Mac session:

- [ ] Install Xcode + CMake + Ninja (`brew install cmake ninja`)
- [ ] Clone mGBA **outside** this repo
- [x] Run `build-mgba-ios.sh` → XCFramework on Mac mini at `App/Vendor/Output/mGBA.xcframework` (local only, 2026-09-08)
- [ ] Create/open iOS App target; follow `XCODE.md` (path documented for Mac mini Output/)
- [ ] Set bridging header + `RETROPLAY_HAS_MGBA` + `MGBANativeBootstrap.registerIfAvailable()`
- [ ] Verify `MGBANativeDriver` builds against the XCFramework (native glue is in-repo under `#if RETROPLAY_HAS_MGBA`)
- [ ] Import a GBA you own via Files → playable frames

---

## One-shot build (copy/paste)

```bash
# 1) Check out RetroPlay
git clone https://github.com/daniel-zn/retroplay.git ~/src/retroplay
cd ~/src/retroplay

# 2) Clone mGBA outside the repo (shallow is fine)
git clone --depth 1 https://github.com/mgba-emu/mgba.git ~/src/mgba

# 3) Build XCFramework into App/Vendor/Output/ (gitignored)
export RETROPLAY_ROOT=~/src/retroplay
export MGBA_SRC=~/src/mgba
./App/Vendor/build-mgba-ios.sh
```

Expect: `App/Vendor/Output/mGBA.xcframework`.

Then open `App/Vendor/XCODE.md` for linking + `RETROPLAY_HAS_MGBA`.

---

## Rules

1. Do not commit the full mGBA tree into this repo unless you decide to.
2. Prefer not to commit the XCFramework either until you want teammates to skip the build.
3. Keep MPL 2.0 attribution in app acknowledgements.
4. App Store path: no JIT; mGBA interpreter is fine for GBA.

## Upstream CMake knobs

`LIBMGBA_ONLY=ON` (used by the script) forces static lib, no Qt/SDL, deps off. Public API lives in `include/mgba/core/core.h` (`mCoreFind`, `mCoreLoadFile`, `runFrame`, keys, saves).

## Manual CMake (same as the script)

See comments inside `build-mgba-ios.sh` or re-run with `bash -x` if a flag fails on your Xcode version. Deployment target default: **iOS 18**.

## After the framework exists

1. Follow **`XCODE.md`** (app target, frameworks, bridging header, Swift flag).
2. Implement native calls behind `#if RETROPLAY_HAS_MGBA` in `MGBACore.swift`.
3. Acceptance: user-imported `.gba` → frames, pause/resume, SRAM under `Documents/Saves`.

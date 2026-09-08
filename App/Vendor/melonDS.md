# melonDS for RetroPlay (M2 NDS) — home Mac build

RetroPlay’s NDS core is **[melonDS](https://melonds.kuribo64.net/)** ([melonDS-emu/melonDS](https://github.com/melonDS-emu/melonDS)).

**App Store path:** **interpreter only** — **no JIT**. BIOS optional for many titles (document when required).

Agents do **not** build this on Linux. When you are at a Mac, run the steps below.

This repo does **not** contain a prebuilt XCFramework or the melonDS source tree.

---

## Checklist — ready for home Mac build

Repo state (already on `main`):

- [x] `App/Vendor/build-melonds-ios.sh` — helper toward `melonDS.xcframework`
- [x] `MelonDSCore` + `MelonDSNativeDriving` / `MelonDSNativeRegistry` + `CoreFactory` → `.nds`
- [x] `NDSFamilyPadView` (portrait first; touch stub) + Play wiring; save/FF gated off until native OK
- [x] AppHost `MelonDSNativeBootstrap` / `MelonDSNativeDriver` (no-op without `RETROPLAY_HAS_MELONDS`)
- [x] `App/Vendor/Output/` gitignored

Your Mac session:

- [ ] Install Xcode + CMake + Ninja (`brew install cmake ninja`)
- [ ] Clone melonDS **outside** this repo
- [ ] Run `build-melonds-ios.sh` (or upstream iOS/CMake build → pack XCFramework)
- [ ] On Mac: add framework + `RETROPLAY_HAS_MELONDS` per `XCODE.md`, then `./AppHost/bootstrap-xcode.sh`
- [ ] Device/sim smoke with a user-owned `.nds` (never commit ROMs)

---

## One-shot build (copy/paste)

```bash
# 1) Check out RetroPlay
git clone https://github.com/daniel-zn/retroplay.git /Users/danielsmacmini/GitHub/retroplay
cd /Users/danielsmacmini/GitHub/retroplay

# 2) Clone melonDS outside the repo
git clone --depth 1 https://github.com/melonDS-emu/melonDS.git /Users/danielsmacmini/GitHub/melonDS

# 3) Build / pack XCFramework into App/Vendor/Output/ (gitignored)
export RETROPLAY_ROOT=/Users/danielsmacmini/GitHub/retroplay
export MELONDS_SRC=/Users/danielsmacmini/GitHub/melonDS
./App/Vendor/build-melonds-ios.sh
```

Expect: `App/Vendor/Output/melonDS.xcframework` once the script’s lib paths are filled after a successful upstream build.

Then open `App/Vendor/XCODE.md` for linking + `RETROPLAY_HAS_MELONDS`.

---

## Rules

1. Do not commit the full melonDS tree into this repo unless you decide to.
2. Prefer not to commit the XCFramework either until teammates should skip the build.
3. Keep OSS attribution in app acknowledgements.
4. App Store path: interpreter only — never enable JIT for store builds.

## After the framework exists

1. Follow **`XCODE.md`** (app target, frameworks, Swift flag `RETROPLAY_HAS_MELONDS`).
2. Implement real native calls in `AppHost/Sources/MelonDSNativeDriver.swift` behind `#if RETROPLAY_HAS_MELONDS`.
3. Flip `MelonDSCore.supportsSaveState` / `supportsFastForward` when save/FF work.
4. Wire dual-screen layout + real touch mapping in Play (stub exists on the pad).
5. Acceptance: user-imported `.nds` → frames, pause/resume, face/D-pad + touch.

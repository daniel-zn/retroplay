# mupen64plus-next for RetroPlay (M2 N64) — home Mac build

RetroPlay’s N64 core is **[mupen64plus-next](https://docs.libretro.com/library/mupen64plus/)** (libretro / mupen64plus family) with **GLideN64** (OpenGL ES HLE).

**App Store path:** `cached_interpreter` only — **no dynarec / JIT**. Do **not** use paraLLEl-RDP (Vulkan LLE) as the iPhone default.

Agents do **not** build this on Linux and do **not** ask anyone else to build it for you. When you are at a Mac (miniMac or MacBook), run the steps below.

This repo does **not** contain a prebuilt XCFramework or the upstream source tree.

---

## Checklist — ready for home Mac build

Repo state (already on `main`):

- [x] `App/Vendor/build-mupen64plus-ios.sh` — helper toward `mupen64plus.xcframework`
- [x] `N64Core` + `N64NativeDriving` / `N64NativeRegistry` + `CoreFactory` → `.n64`
- [x] `N64FamilyPadView` + Play wiring; save/FF gated off until native OK
- [x] AppHost `N64NativeBootstrap` / `N64NativeDriver` (no-op without `RETROPLAY_HAS_N64`)
- [x] `App/Vendor/Output/` gitignored

Your Mac session:

- [ ] Install Xcode + CMake + Ninja (`brew install cmake ninja`)
- [ ] Clone mupen64plus-next / GLideN64 **outside** this repo
- [ ] Run `build-mupen64plus-ios.sh` (or upstream iOS build → pack XCFramework)
- [ ] On Mac: add framework + `RETROPLAY_HAS_N64` per `XCODE.md`, then `./AppHost/bootstrap-xcode.sh`
- [ ] Device/sim smoke with a user-owned `.z64` (never commit ROMs)

---

## One-shot build (copy/paste)

```bash
# 1) Check out RetroPlay
git clone https://github.com/daniel-zn/retroplay.git /Users/danielsmacmini/GitHub/retroplay
cd /Users/danielsmacmini/GitHub/retroplay

# 2) Clone upstream outside the repo (adjust URL if you vendor a specific fork)
git clone --depth 1 https://github.com/libretro/mupen64plus-libretro-nx.git /Users/danielsmacmini/GitHub/mupen64plus-next

# 3) Build / pack XCFramework into App/Vendor/Output/ (gitignored)
export RETROPLAY_ROOT=/Users/danielsmacmini/GitHub/retroplay
export MUPEN_SRC=/Users/danielsmacmini/GitHub/mupen64plus-next
./App/Vendor/build-mupen64plus-ios.sh
```

Expect: `App/Vendor/Output/mupen64plus.xcframework` once the script’s lib paths are filled after a successful upstream iOS build.

Then open `App/Vendor/XCODE.md` for linking + `RETROPLAY_HAS_N64`.

---

## Rules

1. Do not commit the full upstream tree into this repo unless you decide to.
2. Prefer not to commit the XCFramework either until teammates should skip the build.
3. Keep OSS attribution in app acknowledgements.
4. App Store path: **cached_interpreter** + GLideN64/GLES — never enable dynarec or paraLLEl-RDP for store builds.

## After the framework exists

1. Follow **`XCODE.md`** (app target, frameworks, Swift flag `RETROPLAY_HAS_N64`).
2. Implement real native calls in `AppHost/Sources/N64NativeDriver.swift` behind `#if RETROPLAY_HAS_N64`.
3. Flip `N64Core.supportsSaveState` / `supportsFastForward` when save/FF work.
4. Acceptance: user-imported `.z64` / `.n64` / `.v64` → frames, pause/resume, pad + stick.

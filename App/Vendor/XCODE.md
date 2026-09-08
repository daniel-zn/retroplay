# Xcode app host (automated on Mac)

## Already on Mac mini

- Repo: `/Users/danielsmacmini/GitHub/retroplay` (pull before generating)
- XCFramework: `App/Vendor/Output/mGBA.xcframework`
- PPSSPP XCFramework: Mac-local when built (see `PPSSPP.md`)

## One-shot (miniMac)

```bash
cd /Users/danielsmacmini/GitHub/retroplay
git pull --ff-only
./AppHost/bootstrap-xcode.sh
```

That installs XcodeGen if needed, writes `RetroPlay.xcodeproj`, and opens it. Select any iPhone simulator → Run.

`project.yml` already sets:

- Bridging header `AppHost/Supporting/RetroPlay-Bridging-Header.h`
- `RETROPLAY_HAS_MGBA` / `RETROPLAY_HAS_PPSSPP`
- Links local `App/` package (`RetroPlayCore` + `RetroPlayApp`)
- Links `mGBA.xcframework` / `PPSSPP.xcframework` (Do Not Embed)

`@main` calls:

- `MGBANativeBootstrap.registerIfAvailable()`
- `PPSSPPNativeBootstrap.registerIfAvailable()`
- `N64NativeBootstrap.registerIfAvailable()` — no-op until `RETROPLAY_HAS_N64`
- `MelonDSNativeBootstrap.registerIfAvailable()` — no-op until `RETROPLAY_HAS_MELONDS`

## N64 / NDS flags (M2 — enable after XCFrameworks exist)

Do **not** turn these on in `project.yml` until the frameworks exist on disk (build would fail to link).

| Flag | Framework | Bootstrap | Docs / script |
|------|-----------|-----------|---------------|
| `RETROPLAY_HAS_N64` | `App/Vendor/Output/mupen64plus.xcframework` | `N64NativeBootstrap` | `mupen64plus.md`, `build-mupen64plus-ios.sh` |
| `RETROPLAY_HAS_MELONDS` | `App/Vendor/Output/melonDS.xcframework` | `MelonDSNativeBootstrap` | `melonDS.md`, `build-melonds-ios.sh` |

When ready on Mac:

1. Build XCFrameworks with the Vendor scripts (cached_interpreter + GLideN64/GLES for N64; melonDS interpreter, no JIT).
2. Add framework deps in `project.yml` (Do Not Embed), mirror mGBA/PPSSPP.
3. Append `RETROPLAY_HAS_N64` / `RETROPLAY_HAS_MELONDS` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (Debug + Release) and matching `GCC_PREPROCESSOR_DEFINITIONS` if the C bridge needs them.
4. Extend the bridging header only when native headers are available (do not import missing headers).
5. `xcodegen generate` → implement real drivers behind `#if RETROPLAY_HAS_*`.
6. Flip `supportsSaveState` / `supportsFastForward` on `N64Core` / `MelonDSCore` when those paths work.

## If the simulator build fails

Paste the compiler error to the RetroPlay product bot (via Engineer). Do not ask Daniel for intermediate steps — fix on `main`, then `git pull` and rebuild.

## Save states + fast-forward (Play)

- Quick Save / Quick Load write `Documents/Saves/<system>/<gameUUID>/quick.state` (sandbox only; never git).
- mGBA: `mCoreSaveStateNamed` / `mCoreLoadStateNamed` via `VFileOpen`.
- PPSSPP: synchronous `SaveState::SaveToRam` / `LoadFromRam` through `RetroPlayPPSSPPBridge`.
- Fast-forward runs 4 emulated frames per host tick (and ~90 Hz host timer) when toggled (GBA + PSP). UI present rate may stay near 60; judge by in-game motion.
- N64/NDS: Swift hosts + pads land in M2 scaffolding; `supportsSaveState` / `supportsFastForward` stay **false** until native drivers work. Play gates Save/FF on those flags.
- Save/load run on the core GCD queue (same as runFrame) so PPSSPP CoreTiming is not raced from MainActor.

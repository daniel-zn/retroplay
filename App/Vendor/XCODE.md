# Xcode app host (automated on Mac)

## Already on Mac mini

- Repo: `/Users/danielsmacmini/GitHub/retroplay` (pull before generating)
- XCFramework: `App/Vendor/Output/mGBA.xcframework`

## One-shot (miniMac)

```bash
cd /Users/danielsmacmini/GitHub/retroplay
git pull --ff-only
./AppHost/bootstrap-xcode.sh
```

That installs XcodeGen if needed, writes `RetroPlay.xcodeproj`, and opens it. Select any iPhone simulator → Run.

`project.yml` already sets:

- Bridging header `AppHost/Supporting/RetroPlay-Bridging-Header.h`
- `RETROPLAY_HAS_MGBA`
- Links local `App/` package (`RetroPlayCore` + `RetroPlayApp`)
- Links `mGBA.xcframework` (Do Not Embed)

`@main` calls `MGBANativeBootstrap.registerIfAvailable()`.

## If the simulator build fails

Paste the compiler error to the RetroPlay product bot (via Engineer). Do not ask Daniel for intermediate steps — fix on `main`, then `git pull` and rebuild.

## Save states + fast-forward (Play)

- Quick Save / Quick Load write `Documents/Saves/<system>/<gameUUID>/quick.state` (sandbox only; never git).
- mGBA: `mCoreSaveStateNamed` / `mCoreLoadStateNamed` via `VFileOpen`.
- PPSSPP: synchronous `SaveState::SaveToRam` / `LoadFromRam` through `RetroPlayPPSSPPBridge`.
- Fast-forward runs 3 emulated frames per host tick when toggled (GBA + PSP). N64/NDS stay stubs with honest UI.

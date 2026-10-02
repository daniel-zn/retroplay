# Xcode project

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and isn't committed.

```bash
./AppHost/bootstrap-xcode.sh     # installs XcodeGen if needed, generates and opens the project
```

Build the cores first (`App/Vendor/*.md`); `project.yml` expects them in `App/Vendor/Output/`:

| Framework | Compile condition | Driver |
|---|---|---|
| `mGBA.xcframework` | `RETROPLAY_HAS_MGBA` | `MGBANativeDriver` |
| `melonDS.xcframework` | `RETROPLAY_HAS_MELONDS` | `MelonDSNativeDriver` |
| `mupen64plus.xcframework` (embedded framework) | `RETROPLAY_HAS_N64` | `N64NativeDriver` |
| `PPSSPP.xcframework` | `RETROPLAY_HAS_PPSSPP` | `PPSSPPNativeDriver` |

The app target links the local `App/` Swift package (`RetroPlayCore`, `RetroPlayApp`) and uses the
bridging header `AppHost/Supporting/RetroPlay-Bridging-Header.h`. Each `*NativeBootstrap` registers
its driver at launch; without the compile condition it's a no-op.

Tests: `xcodebuild test -project RetroPlay.xcodeproj -scheme RetroPlay -destination 'platform=iOS Simulator,name=<device>'`.

## Save states and fast-forward

- Quick saves live under `Documents/States/<system>/<game UUID>/`: `quick.state` is the latest and
  `quick-1.state` … `quick-4.state` are older ones (pause menu → Saves). Saves → Reset removes them.
- Save and load run on the emulation thread between frames.
- Fast-forward runs three emulated frames per tick (`docs/PLAY-RUNTIME.md`).

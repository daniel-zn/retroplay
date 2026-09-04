# Xcode — drop in `mGBA.xcframework`

Do this on your Mac after `./App/Vendor/build-mgba-ios.sh` succeeds.

## 1. App target

SwiftPM `App/Package.swift` only ships libraries. Create an **iOS App** in Xcode:

1. File → New → Project → App (iOS), product name **RetroPlay**, interface SwiftUI, language Swift.
2. Add local package: File → Add Package Dependencies → Add Local → select the `App/` folder (the one with `Package.swift`).
3. Link products: `RetroPlayCore` (and `RetroPlayApp` if you use `RetroPlayRootView` as the root).

Or: add the `App/Sources/**` files directly into the app target if you prefer no package reference.

Minimum deployment: **iOS 18** (Liquid Glass UI still gated to iOS 26 at runtime).

## 2. Add the XCFramework

1. Drag `App/Vendor/Output/mGBA.xcframework` into the app target (or Project → General → Frameworks).
2. **Do Not Embed** is typical for a static XCFramework.
3. Confirm `FRAMEWORK_SEARCH_PATHS` / Frameworks list shows `mGBA`.

## 3. Bridging header

1. Build Settings → **Objective-C Bridging Header**  
   set to: `Vendor/Bridging/RetroPlay-Bridging-Header.h`  
   (path relative to the app project; copy the header into the app tree if Xcode complains).
2. Header contents import `<mgba/core/core.h>` etc. (already in repo).

## 4. Compiler flag

Build Settings → **Swift Compiler – Custom Flags** → Active Compilation Conditions (Debug & Release):

```text
RETROPLAY_HAS_MGBA
```

That enables the `#if RETROPLAY_HAS_MGBA` branches in `MGBACore.swift`.

## 5. Info / Files access

- Enable importing via the existing `.fileImporter` UI (already in `RetroPlayRootView`).
- No ROM files belong in the project bundle.

## 6. First native glue

In `MGBACore.loadROM` / `start` (under `#if RETROPLAY_HAS_MGBA`):

1. `mCoreFind` / `mCoreLoadFile` with the sandbox ROM path.
2. Configure video buffer; each tick `core->runFrame`; push pixels through `EmulatorFrameSink` / `FrameBitmap`.
3. Map `GBAInput` → `core->setKeys`.
4. SRAM via `SavePaths` + `mCoreAutoloadSave` / save file APIs.

Until those TODOs are filled, the app still reports an honest error even with the flag set.

## 7. Smoke test

1. Run on simulator or device.
2. Import a GBA you own (Files).
3. Open Play — expect frames once native glue is done; before that, clear error about missing glue/framework.

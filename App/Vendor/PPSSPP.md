# PPSSPP (PSP) — Mac build notes

**Status (2026-09-07):** Swift host scaffold landed (`PPSSPPCore`, `PPSSPPNativeRegistry`, IR defaults in `PPSSPPDefaults`). No XCFramework in git yet.

## App Store rule

- Use **IR caching interpreter only** (`CPUCore = 2`). No dynarec / JIT on App Store builds.
- See `PPSSPPDefaults.appStoreIniSnippet`.

## Mac work (not on the Linux bot)

1. Clone upstream PPSSPP on the Mac mini (do not commit the tree into retroplay).
2. Produce an iOS + Simulator XCFramework (static preferred), place at:
   `App/Vendor/Output/PPSSPP.xcframework` (gitignored under Output/).
3. App host: bridging / C++ bridge, `RETROPLAY_HAS_PPSSPP`, implement `PPSSPPNativeDriving`, register in app init:
   `PPSSPPNativeRegistry.makeDriver = { … }`.
4. Smoke with a **user-owned** ISO/CSO/PBP (example title for QA: *ATV Offroad Fury Pro*). Never commit ROMs.

## Until the framework exists

Tapping a PSP library tile shows a clear error from `PPSSPPCore` (driver not registered). Import + library filtering already work.

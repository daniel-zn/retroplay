# Bridging header

App target only (SPM package does not see this header).

1. Link `App/Vendor/Output/mGBA.xcframework` (on Mac mini already built under that path).
2. Set Objective-C Bridging Header → `RetroPlay-Bridging-Header.h`.
3. Add Swift flag `RETROPLAY_HAS_MGBA`.
4. Call `MGBANativeBootstrap.registerIfAvailable()` from `@main` app init.

See `../XCODE.md`.

N64 / NDS bridging headers are added only after Mac XCFrameworks exist — see `../mupen64plus.md`, `../melonDS.md`, and `../XCODE.md` (`RETROPLAY_HAS_N64`, `RETROPLAY_HAS_MELONDS`).

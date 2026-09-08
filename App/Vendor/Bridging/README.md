# Bridging header

App target only (SPM package does not see this header).

1. Link `App/Vendor/Output/mGBA.xcframework` (on Mac mini already built under that path).
2. Set Objective-C Bridging Header → `RetroPlay-Bridging-Header.h`.
3. Add Swift flag `RETROPLAY_HAS_MGBA`.
4. Call `MGBANativeBootstrap.registerIfAvailable()` from `@main` app init.

See `../XCODE.md`.

# Bridging mGBA into the iOS app target

1. miniMac (or another Mac) produces `App/Vendor/Output/mGBA.xcframework` via `../build-mgba-ios.sh`.
2. Create / open an iOS **App** target that depends on `RetroPlayCore`.
3. Add `mGBA.xcframework` to the app target frameworks list.
4. Set **Objective-C Bridging Header** to `App/Vendor/Bridging/RetroPlay-Bridging-Header.h` (copy into the app target if needed).
5. Set `RETROPLAY_HAS_MGBA=1` in Swift Active Compilation Conditions for that target (enables native path in `MGBACore`).
6. Build and run on device/simulator.

Until step 1 completes, `MGBACore` stays on the honest `notImplemented` path.

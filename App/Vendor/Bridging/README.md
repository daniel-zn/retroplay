# Bridging header

Used by the **iOS App** target after you build `mGBA.xcframework` on your Mac.

1. Run `../build-mgba-ios.sh` (see `../mGBA.md`).
2. Follow `../XCODE.md`.
3. Point the app’s Objective-C Bridging Header at `RetroPlay-Bridging-Header.h`.
4. Add Swift flag `RETROPLAY_HAS_MGBA`.

Until the XCFramework is linked, leave the flag off; `MGBACore` stays on the `notImplemented` path.

# Vendoring mGBA (M1)

RetroPlay’s GBA path uses **[mGBA](https://mgba.io/)** ([GitHub: mgba-emu/mgba](https://github.com/mgba-emu/mgba), MPL 2.0).

## Rules

- Do **not** commit the full mGBA source tree into this repo until Daniel asks (keep git lean).
- Build mGBA as a static library / XCFramework on a Mac with Xcode, then link it from the iOS app target.
- Keep license attribution (MPL 2.0) in the app’s acknowledgements.

## Suggested local workflow (Mac)

1. Clone mGBA outside this repo (or as a git submodule later if asked).
2. Configure an iOS arm64 / simulator build of `libmgba` (CMake + Apple toolchain).
3. Add the library + public headers to the Xcode app target that depends on `RetroPlayCore`.
4. Replace the body of `MGBACore` with calls into mGBA’s C API (load ROM bytes, run frame, audio/video callbacks, SRAM).
5. Wire `CoreFactory.makeCore(for:)` (already returns `MGBACore` for `.gba`) into the play UI once frames render.

## Acceptance for M1

- Import a user-owned `.gba` via Files.
- Tap game → playable frames (not `StubEmulatorCore` / notImplemented).
- Pause, resume, SRAM save/load.
- No ROM dumps in git.

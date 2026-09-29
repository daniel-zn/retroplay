# Contributing to RetroPlay

Thanks for helping. A few ground rules:

- **License.** RetroPlay is GPL-3.0-or-later. By submitting a contribution you agree that it is
  licensed under the same terms, and that you have the right to submit it.
- **No game files.** Never commit or attach ROMs, disc images, BIOS or firmware, or links to
  them. Use homebrew or games you own for testing, and keep them out of the repository.
- **Core changes.** Changes to an emulator core belong upstream where possible. If RetroPlay needs
  a local patch, add it under `App/Vendor/patches/`, list it in `App/Vendor/SOURCES.md`, and mark
  modified files as required by their licenses.
- **Third-party code.** When adding or updating a bundled component, update
  `docs/licensing/inventory.json` and run `App/Vendor/generate-license-bundle.py` so the app's
  license screen and `THIRD_PARTY_NOTICES.md` stay complete.
- **Tests.** Run the test suite (`xcodebuild test -scheme RetroPlay`) before opening a pull
  request.

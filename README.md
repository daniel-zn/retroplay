# RetroPlay

Native iPhone SwiftUI emulator with a library-first UX: import games, tap to play, and let the app pick the system automatically. No core picker in the main path. Liquid Glass UI on modern iOS.

First systems:

- Game Boy Advance (mGBA)
- Nintendo 64 (mupen64plus-next)
- Nintendo DS (melonDS)
- PSP (PPSSPP, IR interpreter / no JIT)

**License:** see `LICENSE`. Do not distribute copyrighted ROMs or BIOS dumps with this project.

Agent planning notes live in [grok-things `Projects/retroplay/`](https://github.com/daniel-zn/grok-things/tree/main/Projects/retroplay) as a thin pointer. **This repository is the source of truth for the app.**

See `SPEC.md` for product and engineering detail. Swift M0 scaffold: `App/` (no core binaries yet).

On-screen GBA control layouts: [`docs/CONTROLS-GBA.md`](docs/CONTROLS-GBA.md).

PSP / PPSSPP (IR) scaffold: [`App/Vendor/PPSSPP.md`](App/Vendor/PPSSPP.md).

### GBA / mGBA (M1)

When you are on a Mac, follow the checklist in [`App/Vendor/mGBA.md`](App/Vendor/mGBA.md) (one-shot script + Xcode drop-in). Do not commit bulky mGBA trees unless you choose to.


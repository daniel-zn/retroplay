# N64 / NDS on-screen controls

**Date:** 2026-09-08 (PT)

N64 and NDS no longer share one pad design (trident + analog vs clamshell + touch). Full notes:

- [`CONTROLS-N64.md`](CONTROLS-N64.md) — trident, stick well, C cluster, Z, color cues
- [`CONTROLS-NDS.md`](CONTROLS-NDS.md) — DS face diamond, shoulders, rectangular touch panel

`ConsolePad` switches on `SystemID`. Input bits are unchanged (`N64Input`, `NDSInput`); stick and DS touch now travel in `EmulatorInputState`. See [`PLAY-RUNTIME.md`](PLAY-RUNTIME.md).

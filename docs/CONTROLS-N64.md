# N64 on-screen controls

**Date:** 2026-09-08 (PT)  
**Scope:** Authentic Nintendo 64 pad for RetroPlay Play UI. Portrait-first. Landscape kept working, not the design target.  
**Code:** `N64FamilyPadView` / `N64HoldPad` via `ConsolePadHost` (`.n64`). Bits: `N64Input` + `N64AnalogStick` → `setN64Input`.

See also [`CONTROLS-NDS.md`](CONTROLS-NDS.md). Combined pointer: [`CONTROLS-N64-NDS.md`](CONTROLS-N64-NDS.md).

---

## Hardware baseline (NUS-005)

The N64 pad is a **three-pronged (“trident” / M-shape)** controller, not a SNES rectangle and not two D-pads.

| Control | Hardware placement | Color cue (standard grey pad) |
|---------|--------------------|-------------------------------|
| **Control Stick** | Center prong, octagonal gate | Grey/black nub |
| **+ Control Pad** | Left prong | Grey |
| **A** | Right prong, large, lower-right | **Blue** |
| **B** | Right prong, smaller, above-left of A | **Green** |
| **C▲ C◀ C▶ C▼** | Right prong, yellow diamond **above** A/B | **Yellow** |
| **START** | Center, just above the stick | **Red** |
| **L / R** | Top shoulders on the left/right prongs | Grey |
| **Z** | Trigger on the **back of the center prong** | Dark |

Ten digital buttons + stick: A, B, Start, C-up/down/left/right, L, R, Z, D-pad, analog.

Nintendo’s booklet documents **three hold positions** (not every control is reachable in one grip):

1. **Right** (center + right prongs) — stick, A/B/C, R, Z. Default for 3D (e.g. *Super Mario 64*).
2. **Home** (outer prongs) — D-pad, face, L/R. 2D / SNES-like.
3. **Left** (center + left) — stick + D-pad + L + Z (some FPS).

Portrait Play cannot offer three physical grips; it **shows the whole trident at once** so every bit stays reachable.

---

## Portrait mapping (trident, not stacked D-pads)

Three columns under the game frame, shoulders on top:

```
 [ L ]                              [ R ]

  D-pad          START (red)         C yellow diamond
                 analog well
                 Z trigger           B green   A blue
```

- **Stick** is a circular nub in an **octagonal well**, drag → `N64AnalogStick` (not a second plus pad).
- Magnitude matches the old digital scaffold (**±80**) via `PadHitTesting.analog`; deadzone ~12% of radius; screen-Y down maps to stick-Y up.
- Z is a dark bar **under the stick** (center prong stand-in), not a third shoulder in the L/R row.
- C buttons stay four small circles (that is authentic). D-pad is a **plus**, not four circles.

Hit targets: stick well ≥ 88 pt; D-pad span ≥ 110 pt; A ≥ 52 pt; B/C/L/R/Z ≥ 44 pt height.

### Landscape

Left column: L, D-pad, stick. Center: Start. Right: R, A/B, C cluster, Z. Same widgets as portrait.

---

## Bits

`N64Input` matches mupen64plus-core `m64p_plugin.h` BUTTON flags (`dpadRight/Left/Down/Up`, `start`, `z`, `b`, `a`, `cRight/Left/Down/Up`, `r`, `l`). Stick is `N64AnalogStick` (−128…127; UI uses ±80). Unchanged wiring: `N64Core.setN64Input` → native `setKeys`.

---

## Sources (retrieved 2026-09-08)

- Nintendo 64 Instruction Booklet (NA): Control Stick, + Control Pad, A/B/C/START/L/R/Z; three hold positions; Control Stick must be neutral at power-on; L+R+START recalibrates. Scanned copies widely archived, e.g. [Nintendo 64 user manual](https://usersmanualguide.com/nintendo/game-console/64/user-manual/s76n)
- Wikipedia, *Nintendo 64 controller* (NUS-005; trident; C-buttons; three grips) — [en.wikipedia.org/wiki/Nintendo_64_controller](https://en.wikipedia.org/wiki/Nintendo_64_controller)
- iFixit, *Nintendo 64 Controller* (M-shape; analog stick; Z on the back) — [ifixit.com/Device/Nintendo_64_Controller](https://www.ifixit.com/Device/Nintendo_64_Controller)

---

## Out of scope

- Rumble Pak / Controller Pak UI
- Per-game grip presets (Right vs Home vs Left)
- Landscape-first redesign

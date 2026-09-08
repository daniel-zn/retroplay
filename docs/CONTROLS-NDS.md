# NDS on-screen controls

**Date:** 2026-09-08 (PT)  
**Scope:** Authentic Nintendo DS pad for RetroPlay Play UI. Portrait-first. Dual-screen video already lives in Play (`256×384` stacked). Landscape kept working, not the design target.  
**Code:** `NDSFamilyPadView` / `NDSHoldPad` via `ConsolePadHost` (`.nds`). Bits: `NDSInput` + `NDSTouch` → `setNDSInput`.

See also [`CONTROLS-N64.md`](CONTROLS-N64.md). Combined pointer: [`CONTROLS-N64-NDS.md`](CONTROLS-N64-NDS.md).

---

## Hardware baseline (NTR-001 / USG-001)

The DS is a **clamshell with two screens**. Face controls sit on the **lower half**, flanking the **Touch Screen** (bottom LCD). That is not a GBA slab and not an A/B-only face.

| Control | Hardware placement |
|---------|--------------------|
| **Upper LCD** | Top clamshell (video only; not touch) |
| **Touch Screen** | Lower LCD; stylus / pad; **256×192** |
| **+ Control Pad** | Left of the Touch Screen |
| **X / Y / A / B** | Right of the Touch Screen. Nintendo diamond: **X top, Y left, A right, B bottom** |
| **START / SELECT** | Small ovals. Original DS: right of the face cluster. DS Lite: under the D-pad. Portrait uses the Lite-like pair **under the D-pad** so the face diamond stays clear |
| **L / R** | Wide shoulders on the hinge / top of the lower unit |
| Body | Silver / gunmetal (phat + Lite), not GBA indigo |

START/SELECT are **not** a GBA-style center stack between a two-button face. There is **no analog stick** on original DS / DS Lite.

---

## Portrait mapping

Play already stacks both screens in the game bezel. The pad underneath should read as the **lower DS face**, not a GBA clone:

```
 [ L shoulder ]                    [ R shoulder ]

  plus D-pad     SELECT  START      X
                                    Y   A
                                    B

  ┌─────────────────────────────────────────────┐
  │  Touch Screen (rectangle, 256:192 mapping)  │
  └─────────────────────────────────────────────┘
```

- Face is a **four-button diamond**, not A/B only.
- Touch is a **rectangular panel** (bezel + inset), never a circle. Drag maps through `PadHitTesting.ndsTouch` onto 0…255 × 0…191; lift → `NDSTouch.idle`.
- Gunmetal / silver plate; optional SNES-like letter tints (A reddish, B gold, X blue, Y green) so ABXY are readable at a glance.
- Compact: dual-screen video is tall in portrait, so spacing is tighter than GBA/PSP.

### Landscape

L + D-pad left; SELECT·START under the frame; R + face right. Touch panel is portrait-only this pass (landscape height is too tight). Dual-screen video still uses the center column.

---

## Bits

`NDSInput` matches melonDS key order: A B Select Start Right Left Up Down R L X Y. `NDSTouch` is the bottom-screen sample. Unchanged wiring: `MelonDSCore.setNDSInput`.

---

## Sources (retrieved 2026-09-08)

- Nintendo, *Nintendo DS Instruction Booklet* (NA): Control Buttons (+Control Pad, A B X Y, L R, START SELECT); lower LCD is the Touch Screen; stylus only on the lower screen — [csassets.nintendo.com … ds_english](https://csassets.nintendo.com/noaext/image/private/t_KA_PDF/ds_english?_a=DATC1RAAZAA0)
- Nintendo, *Nintendo DSi Operations Manual*: same control set; Touch Screen operation — [assets.nintendo.eu/…/DSiOperationsManual.pdf](https://assets.nintendo.eu/image/upload/v1635390257/NAL/Support/DSiOperationsManual.pdf); [Nintendo Support A_ID 11966](https://en-americas-support.nintendo.com/app/answers/detail/a_id/11966/~/nintendo-dsi-operations-manual)
- Hardware layout summary — [Nintendo Wiki: Nintendo DS](https://nintendo.fandom.com/wiki/Nintendo_DS) (D-pad left of touch screen; ABXY right; L/R on the lower unit)

---

## Out of scope

- Stylus visual / microphone
- GBA slot (Slot-2) controls
- Overlaying D-pad/face onto the video bezel
- Landscape-first redesign

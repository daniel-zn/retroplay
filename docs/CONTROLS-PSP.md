# PSP on-screen controls

**Date:** 2026-09-08 (PT)  
**Scope:** Authentic PlayStation Portable pad for RetroPlay Play UI. Portrait-first. Landscape kept working, not the design target.  
**Code:** `PSPFamilyPadView` / `PSPHoldPad` via `ConsolePadHost` (`.psp`). Bits: `PSPInput` → `setPSPInput` (PPSSPP `CTRL_*`).

---

## Hardware baseline (PSP-1000)

The PSP is a **landscape handheld**: 16:9 screen center, D-pad + analog on the left, Sony diamond on the right, L/R on the top edge, system keys under the screen. Piano black with silver highlights.

Official launch size about **170 × 74 × 23 mm**, ~280 g (Sony IPE, 2004-12-06).

| Control | Hardware placement | Cue |
|---------|--------------------|-----|
| **Analog nub** | Upper left, **above** the D-pad | Small grey stick |
| **Directional buttons** | Left, below the nub | Plus / four-way |
| **△ ○ ✕ □** | Right. Sony diamond: **△ top, ○ right, ✕ bottom, □ left** — **not ABXY letters** | PlayStation colors (△ green, ○ red, ✕ blue, □ pink) on black |
| **L / R** | Top shoulders | Wide |
| **HOME** | Lower left of the face (system) | Silver |
| **SELECT / START** | Under the screen, toward the right-center | Thin silver |
| Screen | 4.3″ 480×272 16:9 | — |

Analog is only for games that support it. HOME opens the system menu (not a game face button).

---

## Portrait mapping

Game frame uses the **full width** (16:9). Pad sits **below**:

```
 [ L shoulder ]                    [ R shoulder ]

  analog nub (stub)                 △
  plus D-pad                      □   ○
                                    ✕

      HOME-ish     SELECT     START
```

- Face uses **△○✕□ glyphs**, never A/B/X/Y.
- Black chassis, silver edges, colored symbol inks.
- **Analog nub** is a **visual stub** this pass: `PSPInput` / `PPSSPPNativeDriver.setKeys` are **button bitmask only**. Do not fake analog by writing unused bits.
- HOME is **chrome only** (not in `PSPInput`); it must not fire game bits.
- SELECT / START stay wired.

Library tab bar is hidden while Play is open. Nav title carries the game name.

### Landscape (deferred polish)

Left L/D-pad · center screen · right R/face. Start/Select under the frame. Same widgets as portrait.

---

## Face geometry

Sony diamond: △ top, ○ right, ✕ bottom, □ left. Center-to-center reach ≈ `0.82 × diameter`. Diameters ≥ 44 pt.

---

## Bits

`PSPInput` matches PPSSPP `CTRL_*` from `sceCtrl.h` (`select`, `start`, `up/right/down/left`, `l`, `r`, `triangle`, `circle`, `cross`, `square`). Bridge calls `__CtrlUpdateButtons` / `rp_ppsspp_set_buttons` on change. Unchanged.

---

## Sources (retrieved 2026-09-08)

- Sony Interactive Entertainment, “PSP™ Enters the Market on December 12, 2004…” (keys: directional buttons, analog stick, △○✕□, L/R, START, SELECT, HOME; 170×23×74 mm) — [sonyinteractive.com press release](https://sonyinteractive.com/en/press-releases/2004/psp-enters-the-market-on-december-12-2004-at-19800-yen-in-japan/) (dated 2004-12-06)
- PlayStation Support, *PSP-E1002/PSP-E1003* instruction manual (analog stick “for games that support analog stick operation”; SELECT / START; face buttons) — [playstation.com/…/ENUK_PSP-E1002_E1003-6.50.pdf](https://www.playstation.com/content/dam/global_pdc/en/corporate/support/manuals/psp-docs/ENUK_PSP-E1002_E1003-6.50.pdf)
- IGN, “PSP Launch Guide: Hardware Guide” (2005-03-24): PSP-1000, 16:9 480×272, directional pad, analog, △○✕□, L/R — [ign.com/articles/2005/03/24/igns-psp-launch-guide-hardware-guide](https://www.ign.com/articles/2005/03/24/igns-psp-launch-guide-hardware-guide)

---

## Out of scope

- Wiring analog / HOME into PPSSPP (`__CtrlSetAnalogX/Y` and home/ps button)
- Volume / Display / Sound / Hold switch chrome
- Landscape-first redesign

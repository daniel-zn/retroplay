# GBA on-screen controls

**Date:** 2026-09-08 (PT)  
**Scope:** Authentic Game Boy Advance pad for RetroPlay Play UI. Portrait-first (phone under-screen). Landscape kept as a thin overlay, not the design target this pass.  
**Code:** `GBAFamilyPadView` via `ConsolePadHost` (`.gba`). Bits: `GBAInput` → `setGBAInput`.

---

## Hardware baseline (original GBA, AGB-001)

The original Game Boy Advance is a **landscape slab**: screen in the center, controls on the face, L/R on the top edge.

| Control | Hardware placement |
|---------|--------------------|
| **+ Control Pad** | Left of the screen |
| **B / A** | Right of the screen. **B left and slightly lower; A right and slightly higher** (Nintendo face pair) |
| **SELECT / START** | Bottom-center under the screen, between D-pad and A/B. Small oblongs; SELECT left, START right; the pair tilts slightly toward each other |
| **L / R** | Top shoulders (L left, R right), not on the face |
| Body | Launch color **Indigo**; later Arctic / Glacier / Fuchsia / Platinum |

Official size about **144.5 × 82 × 24.5 mm** (W×H×D). Controls: D-pad + A, B, L, R, Select, Start (no X/Y, no analog).

GBA SP (AGS-001) is a clamshell but the **play surface stays landscape** when open (D-pad left, A/B right, L/R on the hinge). It does not change the face map.

### Portrait phone mapping (mental model)

The slab is **rotated in the player’s head**, not redrawn as a vertical Game Boy:

1. Game frame on top (Play chrome).
2. Pad cluster **under the screen**, thumbs on the lower corners:
   - **L / R** sit at the **top of the pad cluster** (shoulder stand-ins).
   - **D-pad** left; **A/B** right with A above-right of B.
   - **SELECT / START** center, slightly below the D-pad / face midline (GBA bottom-center).
3. Indigo / purple face accents are intentional so the pad reads as GBA, not a generic circle grid.

Do **not** use a four-button Nintendo diamond (that is DS / later). Do **not** put L/R as face circles.

---

## Touch UI principles (iPhone)

| Principle | RetroPlay application |
|-----------|------------------------|
| Frequent controls ≥ **44×44 pt** | D-pad arms, A/B, L/R meet or exceed 44 pt visual + hit area |
| Secondary ≥ **28×28 pt** | Start / Select may be slightly smaller capsules but stay ≥ 44 pt height where possible |
| Thumbs at lower / side corners | Portrait: pad under screen. Landscape: D-pad left edge, face right edge |
| Avoid Home indicator / Dynamic Island | Keep pad inside safe area; no primary buttons under the home bar |
| Visible press state | Held controls brighten / scale slightly |
| Layout over skins | Plus-shaped D-pad, oblong Start/Select, wide shoulders — not four generic circles |

Sources: Apple HIG game controls (44 / 28 pt) — [Human Interface Guidelines – Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls); WWDC24 “Design advanced games for Apple platforms” — [developer.apple.com/videos/play/wwdc2024/10085/](https://developer.apple.com/videos/play/wwdc2024/10085/).

---

## RetroPlay layout rules (GBA family)

### Portrait (this pass)

1. Indigo chassis plate behind the cluster.
2. **Row 1:** L (left) · R (right) — wide shoulder bars.
3. **Row 2:** plus D-pad (left) · SELECT / START pair (center, slightly low) · A/B cluster (right).
4. A sits upper-right of B (Nintendo face ordering).
5. Transport (Pause / Resume / Stop) stays **below** the pad; unchanged.

### Landscape (deferred polish)

Existing left / screen / right split remains: L+D-pad left, SELECT·START under the frame, R+A/B right. Same glyphs as portrait. Not the design target this pass.

### Spacing

- ≥ 8 pt gap between adjacent primary controls; ≥ 12 pt between D-pad block and face block.
- D-pad outer span ≈ 120–140 pt; face A/B diameters ≈ 52–58 pt.
- D-pad hit testing uses `PadHitTesting.dpad` (diagonals = two bits).

### Bits

`GBAInput` (A B Select Start Right Left Up Down R L). Unchanged.

---

## Sources (retrieved 2026-09-08)

- Nintendo UK, *Game Boy Advance* instruction booklet (EN/DE/FR PDF): labeled START, SELECT, + Control Pad, A, B, L, R — [nintendo.com/eu/…/GBA_Manual_UK_DE_FR.pdf](https://www.nintendo.com/eu/media/downloads/support_1/game_boy_advance_4/GBA_Manual_UK_DE_FR.pdf); index page [Nintendo UK – GBA manuals](https://www.nintendo.com/en-gb/Support/Legacy-system/Game-Boy-Advance-manual-and-additional-documents-619476.html)
- Nintendo UK technical data (dimensions) — [Support – Technical data](https://www.nintendo.com/en-gb/Support/Legacy-system/Technical-data-619479.html)
- HowStuffWorks, “How Game Boy Advance Works” (shift from vertical GB to horizontal slab; L/R shoulders; Indigo launch color) — [electronics.howstuffworks.com/gameboy.htm](https://electronics.howstuffworks.com/gameboy.htm)
- Control-set summaries — [Wikipedia: Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance), [iFixit: Game Boy Advance](https://www.ifixit.com/Device/Game_Boy_Advance)

---

## Out of scope

- Pixel-perfect plastic skins / huge assets
- Haptics / audio click
- Editable skin JSON
- Physical Game Controller profiles (future)
- Landscape-first redesign

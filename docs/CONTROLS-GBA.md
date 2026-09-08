# GBA / Game Boy family on-screen controls

**Date:** 2026-09-07 (PT)  
**Scope:** Layout principles for RetroPlay Play UI (hit targets, spacing, portrait vs landscape). Colors/skins later.  
**Architecture:** Per-console pad views; this note covers the **GBA family** pad used for Game Boy Advance. See also `CONTROLS-PSP.md` and `CONTROLS-N64-NDS.md`.

---

## Hardware baselines

### Classic vertical Game Boy / GBC (portrait reference)

- Body is **portrait**: screen upper half; controls lower half.
- **D-pad** sits left of the lower face; **A/B** on the right (A typically upper-right of the pair, B lower-left).
- **Start / Select** sit between the D-pad and face buttons, below the screen.
- Useful as the mental model for **phone portrait**: thumbs rest on the lower corners; secondary buttons stay center-bottom.

Sources: HowStuffWorks overview of Game Boy vs GBA orientation ([howstuffworks.com](https://electronics.howstuffworks.com/gameboy.htm)); Nintendo legacy product history for vertical GB family form factor.

### Original GBA (landscape slab)

- Official size about **144.5 × 82 × 24.5 mm** (W×H×D).
- **Horizontal** face: screen centered; **eight-way D-pad** left; **A/B** right; **Select / Start** on the face near the bottom center under the screen; **L / R** on the top shoulders.
- Controls: D-pad + six action buttons (A, B, L, R, Select, Start).

Sources:

- Nintendo UK technical data (dimensions) — [nintendo.com Support – Technical data](https://www.nintendo.com/en-gb/Support/Legacy-system/Technical-data-619479.html)
- Wikipedia / repair summaries of control set — [Game Boy Advance](https://en.wikipedia.org/wiki/Game_Boy_Advance), [iFixit GBA](https://www.ifixit.com/Device/Game_Boy_Advance)
- HowStuffWorks on the shift to horizontal layout and L/R shoulders — [howstuffworks.com](https://electronics.howstuffworks.com/gameboy.htm)

### GBA SP

- Clamshell; play surface remains **landscape** when open (D-pad left, face right, shoulders on hinge side). Reinforces landscape-phone grip more than vertical GB.

---

## Touch UI principles (iPhone)

| Principle | RetroPlay application |
|-----------|------------------------|
| Frequent controls ≥ **44×44 pt** | D-pad arms, A/B, L/R meet or exceed 44 pt visual + hit area |
| Secondary ≥ **28×28 pt** | Start / Select may be slightly smaller capsules but stay ≥ 44 pt height where possible |
| Thumbs at lower / side corners | Portrait: pad under screen. Landscape: D-pad left edge, face right edge |
| Avoid Home indicator / Dynamic Island | Keep pad inside safe area; no primary buttons under the home bar |
| Visible press state | Held controls brighten / scale slightly |
| Prefer not to bury gameplay | Landscape overlays hug left/right; screen stays center |

Sources: Apple HIG game controls (44 / 28 pt) — [Human Interface Guidelines – Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls); WWDC24 “Design advanced games for Apple platforms” (tap targets, thumb zones) — [developer.apple.com/videos/play/wwdc2024/10085/](https://developer.apple.com/videos/play/wwdc2024/10085/).

---

## RetroPlay layout rules (GBA family)

### Portrait (Game Boy–style stack)

1. Game frame on top (existing Play chrome).
2. Control strip below, inside safe area:
   - **Row 1:** L (left) · R (right) — shoulder stand-ins.
   - **Row 2:** D-pad (left) · Start/Select stack (center) · A/B cluster (right).
3. A sits upper-right of B (Nintendo face ordering).
4. Transport (Pause / Resume / Stop) stays below the pad, smaller chrome.

### Landscape (GBA / phone landscape)

1. Screen centered (or slightly upper) with letterboxing as needed.
2. **Left third:** D-pad (+ L near top-left).
3. **Right third:** A/B (+ R near top-right).
4. **Under screen / bottom center:** Select · Start.
5. Keep hit targets in thumb arcs; do not place primary buttons in the unreachable center of the glass.

### Spacing

- ≥ 8 pt gap between adjacent primary controls; ≥ 12 pt between D-pad block and face block.
- D-pad outer span ≈ 120–140 pt; face A/B diameters ≈ 56–64 pt.

---

## Later systems (stub hooks only for now)

| System | Why a different pad |
|--------|---------------------|
| **N64** | Analog stick + C-buttons + Z; not a GB face layout |
| **NDS** | Dual screens + touch stylus region; shoulder/face differ |
| **PSP** | Analog nub, extra face row, different shoulder ergonomics |

`ConsolePadHost` switches on `SystemID` so those pads can land without rewriting Play.

---

## Out of scope (this pass)

- Brand-accurate plastic colors / skins
- Haptics / audio click
- Editable skin JSON
- Physical Game Controller profiles (future)


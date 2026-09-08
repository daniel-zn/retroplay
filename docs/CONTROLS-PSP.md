# PSP on-screen controls

## Portrait
1. Game frame uses the **full screen width** (16:9).
2. All controls sit **below** the frame: L/R, D-pad + △○✕□, Select/Start, then Pause/Resume/Stop.

## Landscape (like a real PSP)
1. **Left:** L + D-pad (thumb zone).
2. **Center:** game screen (as wide as remaining space), Select/Start under it, small transport.
3. **Right:** R + △○✕□ face diamond (thumb zone).

## Face order
Sony diamond: △ top, ○ right, ✕ bottom, □ left. Center-to-center reach ≈ `0.82 × diameter` so circles do not overlap.

## Bits
`PSPInput` matches PPSSPP `CTRL_*`. Bridge calls `__CtrlUpdateButtons` on change.

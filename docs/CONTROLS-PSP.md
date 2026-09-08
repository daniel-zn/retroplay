# PSP on-screen controls

## Portrait
1. Game frame (16:9) on top.
2. L · R on the shoulders row.
3. D-pad left · △○✕□ face right (diamond with non-overlapping hit targets).
4. Select · Start centered under the pad.
5. Pause / Resume / Stop under that.

## Landscape (phone landscape)
1. **Left third (thumb):** L above D-pad.
2. **Center:** game screen, then Select · Start, then transport.
3. **Right third (thumb):** R above △○✕□ face diamond.

## Face order
Sony diamond: △ top, ○ right, ✕ bottom, □ left.

Face buttons use a center-to-center reach of about `0.72 × diameter` so circles do not overlap.

## Bits
`PSPInput` raw values match PPSSPP `CTRL_*` (`sceCtrl.h`). The bridge calls `__CtrlUpdateButtons` on change.

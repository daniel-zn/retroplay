# PSP on-screen controls

## Layout

### Portrait
1. Game frame (16:9) on top.
2. L · R shoulders.
3. D-pad · Select/Start · △○✕□ face cluster.

### Landscape
1. Left: L + D-pad.
2. Center: screen.
3. Right: R + face cluster.
4. Under screen: Select · Start.

## Face order
Sony diamond: △ top, ○ right, ✕ bottom, □ left.

## Bits
`PSPInput` raw values match PPSSPP `CTRL_*` (`sceCtrl.h`). The bridge calls `__CtrlUpdateButtons` on change.

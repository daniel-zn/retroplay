# PSP on-screen controls

## Portrait (current focus)
1. Game frame uses the **full screen width** (16:9). SoftGPU pixels fill the bezel.
2. All controls sit **below** the frame: L/R, D-pad + △○✕□, Select/Start, then Pause/Resume/Stop.
3. Library tab bar is hidden while Play is open.
4. Nav title carries the game name (no extra system caption above the bezel).

## Landscape (deferred)
Left L/D-pad · center screen · right R/face — polish later after real Simulator rotate works.

## Face order
Sony diamond: △ top, ○ right, ✕ bottom, □ left. Reach ≈ `0.82 × diameter`.

## Bits
`PSPInput` matches PPSSPP `CTRL_*`. Bridge calls `__CtrlUpdateButtons` on change.

# N64 / NDS on-screen controls (M2 scaffold)

**Date:** 2026-09-08 (PT)  
**Scope:** Portrait-first pad layouts for N64 and NDS. Colors/skins later.

## N64 (`N64FamilyPadView`)

- Shoulders: L / Z / R
- Left: D-pad + crude digital stick (±80 → `N64AnalogStick`)
- Right: Start, A/B face, C-button diamond
- Bits match mupen64plus `m64p_plugin.h` BUTTON flags

## NDS (`NDSFamilyPadView`)

- L/R, D-pad, Select/Start, X/A/B/Y face diamond
- Touch stub strip maps drag → `NDSTouch` (bottom-screen coords); dual-screen Play layout TBD
- Bits match melonDS key order (A B Select Start Right Left Up Down R L X Y)

## Play

`ConsolePadHost` switches on `SystemID`. Save/FF remain disabled (`supports*` false) until native cores register.

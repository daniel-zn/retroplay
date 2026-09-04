# CONTEXT.md — RetroPlay

**Read this first.** Product/engineering detail: `SPEC.md`. App scaffold: `App/`.

**Owner:** Engineer / RetroPlay bots. **Source of truth:** this public repo (`daniel-zn/retroplay`). Thin agent pointer also in `grok-things/Projects/retroplay/`.

Do **not** invent that a binary, IPA, or App Store listing exists. Do **not** distribute ROMs.

---

## Identity

| Field | Value |
|-------|--------|
| **Project** | `retroplay` |
| **Working title** | RetroPlay |
| **Repo** | https://github.com/daniel-zn/retroplay |
| **Area** | native iPhone SwiftUI emulator (App Store–viable) |
| **Started** | 2026-09-04 |
| **Formerly** | GlassPlay (retired name; do not revive `Projects/glassplay/` in grok-things) |

### Purpose

Native iPhone **SwiftUI** emulator with a **library-first** UX (import → tap → play; auto system/core; no core picker), **Liquid Glass** (iOS 26), **locked P0 only**: GBA, N64, NDS, **PSP** (App Store via PPSSPP IR — not sideload-only).

---

## Locked P0 cores

| System | Default core | Rationale |
|--------|--------------|-----------|
| GBA | **mGBA** | MPL 2.0; accuracy/maintenance; interpreter-friendly |
| N64 | **mupen64plus-next** + GLideN64 | `cached_interpreter` + GLES3 HLE; not paraLLEl-RDP default |
| NDS | **melonDS** | Clear JIT-less 1× path on modern iPhone |
| PSP | **PPSSPP** IR (`CPUCore=2`) | Official App Store 2024-05-15; JIT speeds up only |

---

## Constraints

1. App Store first — no JIT; **PSP stays App Store P0**.
2. Library UX; auto ROM → system → one default core; no core picker in normal UI.
3. Bundle cores; no runtime core install.
4. User-imported ROMs via Files only; no invented ROM paths.
5. Do not revive NES/SNES/GB as P0 without scope change.
6. Do not describe RetroPlay as copying another app’s UX; name other projects only for real dependencies/licenses.
7. Commit with author **Daniel Nadeem** `<daniel@danielzn.com>` via with-github.sh when landing.

## Next build step

M0 landed. M1 scaffolding + exact Mac build docs: `App/Vendor/mGBA.md`, `App/Vendor/build-mgba-ios.sh`. Daniel builds mGBA XCFramework himself on a home Mac (miniMac or MacBook). Agents do not loop miniMac for the binary.

## Ready for home Mac build

See checklist at top of `App/Vendor/mGBA.md`. One-shot: clone mGBA outside repo → `build-mgba-ios.sh` → follow `App/Vendor/XCODE.md` (framework + bridging header + `RETROPLAY_HAS_MGBA`).

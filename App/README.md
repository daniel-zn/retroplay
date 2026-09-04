# RetroPlay App scaffold

M0 library shell — **no emulator binaries**, no cloned bulky repos, no ROM dumps.

```
App/
  Package.swift                 # platforms: iOS 18 (Liquid Glass at runtime iOS 26+)
  Sources/
    RetroPlayCore/
      SystemID.swift            # gba, n64, nds, psp
      EmulatorCore.swift        # protocol + StubEmulatorCore + SystemRegistry
      ROMImporter.swift         # extension → LibraryGame
      LibraryStore.swift        # Documents/library.json + Documents/ROMs copies
      ImportContentTypes.swift  # P0 extensions for .fileImporter
      PPSSPPDefaults.swift      # IR_INTERPRETER = 2, no dynarec
    RetroPlayApp/
      AppEntry.swift            # library + fileImporter + Settings + stub alert
      LiquidGlassChrome.swift   # glassEffect when #available(iOS 26, *), else material
```

## M0 behavior

1. **Import** — `.fileImporter` for `gba/agb/mb`, `n64/z64/v64`, `nds/dsi`, `iso/cso/chd/pbp`, `zip`. Picks are copied into the app sandbox `Documents/ROMs/`; rows use `ROMImporter.makeLibraryEntry` with relative paths.
2. **Persist** — `LibraryStore` writes `Documents/library.json`.
3. **Liquid Glass** — toolbar chrome uses `glassEffect` on iOS 26+; ultra-thin material fallback on older OS. Package platform stays iOS 18.
4. **Settings** — Guideline 4.7 / user-imported-only / no ROMs shipped.
5. **Play** — tapping a row shows an honest alert: `StubEmulatorCore` is not playable yet.

## Next

**M1:** vendor/build **mGBA** behind `EmulatorCore` (still do not commit ROM dumps).

See `../SPEC.md` for architecture and milestones.

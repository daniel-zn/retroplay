# RetroPlay App scaffold

Smallest Swift layout for M0 — **no emulator binaries**, no cloned bulky repos.

```
App/
  Package.swift
  Sources/
    RetroPlayCore/
      SystemID.swift          # gba, n64, nds, psp
      EmulatorCore.swift      # protocol + StubEmulatorCore + SystemRegistry
      ROMImporter.swift       # Files-based import stub
      PPSSPPDefaults.swift    # IR_INTERPRETER = 2, no dynarec
    RetroPlayApp/
      AppEntry.swift          # empty library shell stub
```

## Next

1. Open `Package.swift` in Xcode or create an iOS app target that depends on `RetroPlayCore`.
2. Wire `.fileImporter` / document picker → copy into sandbox → `ROMImporter.makeLibraryEntry`.
3. Apply Liquid Glass (`glassEffect`, `GlassEffectContainer`) when building with iOS 26 SDK.
4. M1: vendor/build **mGBA** behind `EmulatorCore` (still do not commit ROM dumps).

See `../SPEC.md` for architecture and milestones.

# RetroPlay App package

Swift package with the platform-neutral runtime (`RetroPlayCore`) and the SwiftUI app (`RetroPlayApp`).
Native cores are linked in the **app target** (`AppHost/`), never here — the package builds without any XCFramework.

```
App/
  Package.swift                     # iOS 18 (+ macOS 15 so `swift test` can run RetroPlayCore)
  Sources/
    RetroPlayCore/
      SystemID.swift                # gba, n64, nds, psp + screen size, aspect, refresh rate
      EmulatorCore.swift            # EmulatorCore protocol, NativeEmulatorCore, CoreFactory
      LibraryStore.swift            # Documents/library.json + Documents/ROMs copies
      SaveStateStore.swift          # Documents/Saves/<system>/<game>/ (quick.state, battery saves)
      Play/
        NativeEmulatorDriver.swift  # protocol the AppHost drivers implement + NativeDriverRegistry
        EmulationThread.swift       # the one emulation thread, deadline frame pacing
        EmulationSession.swift      # per-game run loop: input → frames → audio → video
        AudioRingBuffer.swift       # lock-free SPSC ring (emu thread → audio thread)
        AudioOutput.swift           # AVAudioEngine + dynamic-rate resampler
        VideoFrameStore.swift       # latest-frame mailbox read by the screen's display link
        EmulatorInput.swift         # EmulatorInputState + per-system button bits
        ControllerMapping.swift     # physical controller / keyboard → system buttons
        PadHitTesting.swift         # D-pad / stick / DS touch geometry
    RetroPlayApp/
      AppEntry.swift                # root tabs: library home, search, import, delete
      SettingsView.swift            # grouped settings (display, sound, controls, library, systems)
      Library/                      # tiles + label art, Continue Playing, filter/sort bar, empty states
      PlayView.swift                # full-screen play, layouts, lifecycle
      PlayMenuView.swift            # pause menu
      GameScreenView.swift          # CADisplayLink → CALayer frame presenter
      Controls/                     # pad visuals, multi-touch surface, controllers
  Tests/RetroPlayCoreTests
```

How it fits together: [`../docs/PLAY-RUNTIME.md`](../docs/PLAY-RUNTIME.md).
Building the cores: `Vendor/*.md` and `Vendor/XCODE.md`.

# Play runtime

How a game runs, from a tap on the library to pixels, sound and saves.

## Threads

| Thread | Does |
|--------|------|
| **Main** | SwiftUI, touch, controllers. Never runs a core. |
| **`RetroPlay.Emulation`** (`EmulationThread`) | The only thread that touches a native core: load, run frames, save/load state, teardown. One per app, so PPSSPP / mupen global state and the N64 GL context are never touched from two threads, and a closing game always finishes tearing down before the next one loads. |
| **Audio render** (AVAudioEngine) | Pulls samples from a lock-free ring; never waits on the emulator. |

The UI talks to a game only through `NativeEmulatorCore`, which turns each call (`pause`, `saveState`, `stop`, …) into a work item on the emulation thread.

## Frame loop (`EmulationSession.tick`)

1. Read the latest `EmulatorInputState` (buttons + analog + DS touch) from the input mailbox.
2. `runFrame()` — ×3 while fast-forwarding.
3. Drain audio into the ring (discarded while fast-forwarding or muted).
4. Copy the frame into a reused buffer and publish it to `VideoFrameStore`.
5. Every ~3 s, `flushSaveData()` (drivers skip unchanged saves).
6. Sleep until the next deadline on the monotonic clock. Deadlines are absolute, at the core's real rate (GBA 59.73, DS 59.83, N64 from the core, PSP 59.94). If it falls more than 4 frames behind, it resyncs rather than running a burst.

## Video

`VideoFrameStore` holds only the newest `CGImage` (RGBX, alpha ignored). `GameScreenView` reads it from a `CADisplayLink` and sets it as a layer's `contents` (nearest-neighbour by default, "Smooth Screen" for linear). SwiftUI is not re-rendered per frame.

## Audio

Every core now outputs sound: mGBA (`mAudioBuffer`, ~32 kHz), melonDS (`SPU.ReadOutput`, 48 kHz), mupen64plus-next (libretro batch callback, 44.1 kHz), PPSSPP (`System_AudioPushSamples`, 44.1 kHz). `AudioOutput` resamples to 48 kHz with a ±0.5 % dynamic rate adjustment that holds the ring at ~50 ms. That absorbs the drift between the frame timer and the sound card without crackles or growing lag. Settings: Sound on/off, "Mute with Silent Mode".

## Saves

Drivers get `SavePaths` and pick their file from it, so battery-save import (`SaveGameImporter`) and game deletion (`GameArtifactCleanup`) use the same layout. ROMs live in `Documents/Games/`; `SavePaths.migrateLegacyLayout` moves older `ROMs/`, `N64Saves/` and `PPSSPP/` folders into place.

| System | Battery save | Save state |
|--------|--------------|------------|
| GBA | `Saves/<rom path>.sav` (`sramURL`) | mGBA state, loads without overwriting the cartridge save |
| NDS | `Saves/<rom path>.sav` (`sramURL`, written after the game saves) | melonDS `Savestate`, with rollback if a file is bad |
| N64 | `Saves/n64/<rom name>.srm` (`n64SRAMURL`, EEPROM/SRAM/Flash/Pak) | `retro_serialize` |
| PSP | memory stick `Saves/psp-memstick` (`PSP/SAVEDATA`; must not be named "psp", see `SavePaths.pspMemstickDirectory`) | PPSSPP state |

Battery saves are flushed periodically, on pause, when the app backgrounds and on quit. Save states live in `States/<system>/<game id>/`: `quick.state` is the newest and `quick-1` … `quick-4` are older ones (hold Load in the pause menu). A save is written to `quick.pending.state` first and only then rotated in, so a failed save never destroys the previous one. Leaving a game auto-saves; opening it again resumes from that save.

PSP save dialogs: the bridge reports the system as not headless and points PPSSPP at the bundled `assets/ppge_atlas.zim`, so SAVEDATA text and button icons draw. A recoverable CPU error inside a dialog is continued; an unrecoverable one stops the core and Play says so.

## Input

* **Touch:** pad visuals are display-only and report their frames (`padRegion`). One transparent `PadTouchSurface` over the screen owns every pad touch: multi-touch, sliding between face buttons, pressing the gap between two buttons for both, D-pad/stick touches that keep tracking off the graphic, snapping near-misses (14 pt), and a haptic tick per press. Touches away from controls fall through to the menu buttons.
* **Touch analog stick (`TouchStick`):** zero is wherever the thumb lands, not the centre of the graphic; full tilt is ~0.42 × the well size (at least 44 pt) away, with an 8 % deadzone, so partial tilt is easy to hold. Overshooting drags the origin along, so reversing direction is quick. N64 also needs `mupen64plus-astick-sensitivity = 100` from the host: mupen's unset default is 0, which zeroes the stick.
* **DS Touch Screen:** touch the bottom half of the game video.
* **Controllers:** any `GCExtendedGamepad` (MFi, Xbox, DualSense, Switch Pro). Buttons map by position (`ControllerMapping`): GBA/DS A = east, B = south; PSP ✕ = south; N64 A = south, B = west, Z = left trigger, right stick = C buttons. Home opens the menu. The touch pad hides while a controller is connected (toggle in Options).
* **Keyboard:** arrows, Z/X/A/S face, Q/W shoulders, E/R triggers, Return = Start, Right Shift/Delete = Select, I/J/K/L = right stick, Esc = menu. Handy in the Simulator.

## Lifecycle

Play is full screen: no status bar, home indicator hidden, system edge gestures deferred, no swipe-back. The game pauses (and saves flush) when the pause menu opens or the app goes inactive, and resumes when you return.

## Adding a core

Implement `NativeEmulatorDriver` in `AppHost/Sources` behind the core's `RETROPLAY_HAS_*` flag and register it in a `*NativeBootstrap` with `NativeDriverRegistry.register(.system) { Driver() }`. All methods are called on the emulation thread.

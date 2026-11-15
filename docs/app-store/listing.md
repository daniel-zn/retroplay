# RetroPlay: App Store listing (en-US)

The text App Store Connect shows (kept current for each version). `Scripts/asc.py listing` uploads it (fields below,
between the `---` markers, exactly as written). Trademarks appear only as compatibility notes, never
as keywords (App Review guideline 2.3.7).

## Name
RetroPlay Emulator

## Subtitle (30 characters)
---
Play the classics you own
---

## Promotional text (170 characters)
---
Your game library on your iPhone, in Cover Flow. Bring your saves from Files or a network share, play with touch controls built for each system or a controller.
---

## Description
---
RetroPlay plays the classic games you own on your iPhone. Import your game files from Files and start playing: RetroPlay picks the right system for each one and keeps your library organised with box art.

PLAYS
• NES and SNES
• Game Boy Advance
• Nintendo 64
• Nintendo DS, with the touch screen
• Genesis / Mega Drive
• Atari 7800
• PlayStation and PlayStation Portable

BUILT FOR PLAYING
• Touch controls laid out like each system's own, in portrait and landscape, in Liquid Glass or a flat style
• Game controllers: Xbox, PlayStation, Switch Pro and MFi, including menu navigation. Touch controls step aside while a controller is connected
• Save states, automatic in-game saves, and resume where you left off
• Fast forward
• PSP games rendered on the GPU, sharp at your screen's resolution
• AirPlay to a TV

BRING YOUR SAVES
• Import saves from Files, iCloud Drive or a network share: pick a folder and RetroPlay searches it, and every folder inside, for battery saves, memory cards, Nintendo 64 saves and PSP save folders
• Each save is matched to its game, and RetroPlay asks before replacing a save you already have
• Saves for games you haven't added yet are kept and attach when you add the game
• Works with the save files of every system RetroPlay plays

YOUR LIBRARY
• Cover Flow: your games as boxes and cases you flick through, or a grid
• Box art for your games, your own cover pictures, or a box drawn in each system's style
• Filter by system, sort and search
• Everything stays on your iPhone, in RetroPlay's folder in the Files app

PRIVATE
No account, no ads, no tracking, no data collected.

BRING YOUR OWN GAMES
RetroPlay doesn't include, sell or link to any games, BIOS or firmware. Import only software you have the right to use.

RetroPlay is open source under the GPL. Game Boy Advance, Nintendo 64, Nintendo DS, NES, SNES, PlayStation, PlayStation Portable, Genesis, Mega Drive and Atari 7800 are trademarks of their respective owners, used here only to describe compatibility. RetroPlay is not affiliated with or endorsed by Nintendo, Sony, Sega or Atari.
---

## Keywords (100 characters, comma-separated)
---
emulator,retro,classic,console,games,arcade,8-bit,16-bit,handheld,controller,save states,homebrew
---

## URLs
- Support: https://danielzn.com/projects/retroplay/support/
- Marketing: https://danielzn.com/projects/retroplay/
- Privacy policy: https://danielzn.com/projects/retroplay/privacy/

## Category
Games (primary).

## Age rating
4+: the app itself has no objectionable content, ads, chat, web browsing or user accounts. Games
are the player's own imports.

## App Privacy (set by hand in App Store Connect › App Privacy)
Data Not Collected. (Box art lookups send a game title to the libretro thumbnail server; nothing is
linked to the person or stored by the developer.)

## Screenshots
6.9" iPhone (1320 × 2868), from the Simulator with free homebrew test games only (no commercial
games): `docs/app-store/screenshots/`. To take them again, run `Scripts/app-store-screenshots.sh`
in the Simulator's turn line (it narrows the Simulator's library to the homebrew games, runs
AppStoreScreenshotsUITests with the status bar at 9:41, puts the library back and writes
build/app-store-screenshots/). Look at each shot, copy them here, then upload them with
`Scripts/asc.py screenshots build/app-store-screenshots` (it uploads every .png in the folder).

# In-game saves: what each core reads, and what imports

Every core keeps a game's in-game (battery) save in one place, and both imports (the
library's + → Saves and the pause menu's Import Battery Save…) write to that place:
`SavePaths.batterySaveURL(system:romURL:)`, which the drivers boot from and
`SaveFormat.destination` resolves. `SaveFormat` (App/Sources/RetroPlayCore/SaveFormat.swift) is
the table below in code; `SaveFormatPerCoreTests` imports a save for each row, from the folder
layouts other emulators leave, and checks it lands at that path. N64's combined save has its
own page: [N64-SAVES.md](N64-SAVES.md).

## Per core

| System | Core | What the core reads | Extensions | Sizes | Byte order | Installed at |
|---|---|---|---|---|---|---|
| GBA | mGBA | The cartridge's SRAM, EEPROM or Flash, as mGBA's `.sav` (RetroArch's mGBA `.srm` is the same file) | `.sav`, `.srm` | 512 B, 8 KiB (EEPROM); 32 KiB (SRAM); 64 KiB, 128 KiB (Flash); 128 KiB + 16 B (mGBA's RTC block); 133 KiB, 134 KiB | Byte array, as the cartridge has it (EEPROM bits MSB first, as VBA-M writes them) | `Saves/<rom>.sav` |
| NDS | melonDS | The game card's save memory, raw | `.sav`, `.srm` | 512 B, 8 KiB, 64 KiB, 128 KiB, 256 KiB, 512 KiB, 1 MiB, 8 MiB, 32 MiB | Byte array | `Saves/<rom>.sav` |
| N64 | Mupen64Plus-Next | One combined block: EEPROM, 4 Controller Paks, SRAM, FlashRAM | `.srm` (loose `.eep`, `.mpk`, `.sra`, `.fla` are merged in from the library) | 296,960 B | See [N64-SAVES.md](N64-SAVES.md) | `Saves/n64/<rom>.srm` |
| PSP | PPSSPP | `SAVEDATA/<product ID…>/` folders with a PARAM.SFO, found by product ID | folders | — | PPSSPP's own files | `PSP/SAVEDATA/<folder>` |
| NES | Nestopia | The cartridge's battery WRAM (`SAVE_RAM`), raw | `.sav`, `.srm` | 1 B – 1 MiB (8 KiB in practice) | Byte array | `Saves/<rom>.sav` |
| SNES | bsnes | The cartridge's RAM (`SAVE_RAM`), raw; Snes9x's `.srm` is the same | `.sav`, `.srm` | 1 B – 1 MiB (2–128 KiB in practice) | Byte array | `Saves/<rom>.sav` |
| Genesis | clownmdemu | A fixed 64 KiB cartridge-RAM window, indexed by bus address from 0x200000: odd-byte SRAM sits on odd offsets, as Genesis Plus GX writes it | `.sav`, `.srm` | 1 B – 64 KiB | Address-indexed bytes | `Saves/<rom>.sav` |
| Atari 7800 | ProSystem | Nothing: `retro_get_memory_size(SAVE_RAM)` is 0 | none (refused, with why) | — | — | — |
| PS1 | PCSX-ReARMed | Memory card 1 (`pcsx_rearmed_memcard1 = libretro`, the default), a raw card | `.sav`, `.srm`, `.mcr`, `.mcd` | 128 KiB | Raw card image | `Saves/<rom>.sav` |

`<rom>` is the ROM's file name in Games/ without its extension.

## Where other emulators leave saves

The library import matches a save to a game by name, at the strictest level that finds one:
the file name as is, then ignoring case, then the title with region and revision tags,
punctuation and accents dropped (`Pac-Man (USA, Europe).srm` is `Pac-Man.gba`'s). The pause
menu's import takes the same names for its game. Folders named after an emulator or system are
a hint when a name fits games on two systems.

| Emulator | Where | Name |
|---|---|---|
| RetroArch | `saves/<core name>/` (or `saves/`) | `<rom>.srm` |
| mGBA, VBA-M | next to the ROM | `<rom>.sav` |
| melonDS | next to the ROM | `<rom>.sav` |
| Delta | exported from the game's menu | `<game name>.sav` / `.srm` |
| OpenEmu | `OpenEmu/<core>/Battery Saves/` | `<rom>.sav` |
| Snes9x | `Saves/` | `<rom>.srm` |
| FCEUX, Mesen | `sav/`, `Saves/` | `<rom>.sav` |
| DuckStation | `memcards/` | `<title>_1.mcd` (card 1; `_2` is refused: RetroPlay uses card 1) |
| ePSXe | `memcards/` | `<name>.mcr` |
| PPSSPP | `PSP/SAVEDATA/` | one folder per save |

Refused, with what to do: DeSmuME `.dsv` (carries a footer), DexDrive `.gme` (a header),
PS3 `.vmp` (signed), RetroArch rzip-compressed saves, a Genesis save over 64 KiB (the core
would cut it off), sizes no cartridge has.

## Saves for games not in the library

A save whose game isn't in the library is kept when its system is known (its folder or its
name says it, or only one system takes it): battery files in app data under
`KeptSaves/<system>/`, PSP folders straight in SAVEDATA. Settings → Saves lists them, and
deletes them. When a game is added whose name matches one (and no other game's), the save
moves to the game's path above, unless the game has a save there already. PSP slots need no
move: PPSSPP finds them by product ID, so a game imported as CSO or CHD (no product ID read)
doesn't claim its slot.

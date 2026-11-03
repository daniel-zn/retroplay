# N64 saves: the combined .srm and loose files

RetroPlay plays N64 games with Mupen64Plus-Next, which keeps every kind of save for a game in
one file, `<game>.srm`: the core's `save_memory_data` struct written out as is
(`retro_get_memory_data(RETRO_MEMORY_SAVE_RAM)` returns `&saved_memory`).

## Layout

From `External/mupen64plus-next/libretro/libretro_memory.h` and the sizes in
`mupen64plus-core/src/device/` (`cart/sram.h`, `cart/flashram.h`, `controllers/paks/mempak.h`):

| Region | Offset | Size |
|---|---|---|
| EEPROM | 0x00000 | 0x800 (2 KiB; a 4 Kbit cartridge uses the first 512 bytes) |
| Controller Pak 1–4 | 0x00800 + n × 0x8000 | 0x8000 each |
| SRAM | 0x20800 | 0x8000 |
| FlashRAM | 0x28800 | 0x20000 |
| **Total** | | **0x48800 (296,960 bytes)** |

A new save is made the way the core makes one (`libretro.c` `format_saved_memory`): EEPROM,
SRAM and FlashRAM filled with 0xFF (`format_eeprom`, `format_sram`, `format_flashram`), each
Controller Pak formatted by `format_mempak` (ID block with a random serial, device 0x0001,
1 bank, version 0, its checksums and three backups; the index table with pages 5–127 free and
its backup on page 2). `N64CombinedSave.blank()` does the same.

## Byte order in the .srm

- **EEPROM and Controller Paks** are byte arrays: the core `memcpy`s them to and from the save
  (`cart/eeprom.c`, `paks/mempak.c`), so they're in the N64's own order.
- **SRAM and FlashRAM** are copied through RDRAM's host-order words: `mem[(addr+i)^S8] =
  dram[(addr+i)^S8]` (`cart/sram.c`, `cart/flashram.c`). On a little-endian host (every iPhone)
  each 32-bit word's bytes are reversed against the cartridge.

## Loose files from other emulators and flash carts

| File | Size | Region | What's assumed |
|---|---|---|---|
| `.eep` | 512 B or 2 KiB | EEPROM | Copied as is: every emulator and cart writes EEPROM as a byte array. |
| `.mpk` | 32 KiB (one pak) or 128 KiB (four, as Mupen64Plus standalone keeps them) | Controller Pak 1 (or the pak its name ends in: `_2`, ` 3`, `-4`), or all four | Checked, not assumed: a formatted pak's ID block has two checksums. Copied as is when they check out; with its words swapped when only that checks out; refused otherwise. An unformatted slot in a four-pak file is left as it is. |
| `.sra` | 32 KiB | SRAM | Emulator order (Mupen64Plus standalone shares this core's code and writes the same buffer; Project64 also keeps SRAM in little-endian words), copied as is. A file under a flash cart's folder (`ED64`, `EverDrive`, `SummerCart`/`SC64`, `64drive`) is in the cartridge's own big-endian order and has its words swapped. |
| `.fla` | 128 KiB | FlashRAM | As `.sra`. |

SRAM and FlashRAM contents carry no marker that tells the two orders apart, so outside a flash
cart's folder the emulator order is assumed, and the import summary says so for that save
("Byte order assumed from an emulator…") rather than guessing silently.

All the loose files for one game become one import item ("Adds EEPROM, Controller Pak 1").
Importing writes only those regions into the game's `.srm` (or a new blank one) and keeps the
rest; replacing an existing `.srm` follows the summary's replace / keep choice like any save.
Code: `App/Sources/RetroPlayCore/N64CombinedSave.swift`, planned in `LibrarySaveImport.swift`.

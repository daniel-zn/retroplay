// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How one system's core keeps its in-game saves: which files it accepts, which sizes are real,
/// and where the save goes. The one table the save importers (in-game and library) and
/// `SavePaths.batterySaveURL` read; a new core adds an entry here.
public struct SaveFormat: Sendable {
    public enum Layout: Sendable, Equatable {
        /// One battery file per game, named after the ROM (`Saves/<rom>.sav`).
        case batteryFile
        /// PSP: `SAVEDATA/<product ID…>/` folders with a PARAM.SFO, shared by every copy of a game.
        case pspSavedataFolders
    }

    public let system: SystemID
    public let layout: Layout
    /// Battery-file extensions this core's saves come with (lower case, no dot). A library
    /// scan only takes these.
    public let extensions: Set<String>
    /// Exact byte counts a real save can have.
    public let sizes: Set<Int>
    /// Byte ranges a real save can have (for formats with optional trailers).
    public let sizeRanges: [ClosedRange<Int>]
    /// Extensions that are saves for this system but can't be used as they are, with why.
    public let unusableExtensions: [String: String]
    /// What the in-game import (the player picked this file for this game) took before this
    /// table existed: any of `legacyExtensions`, and for the libretro cartridge systems any
    /// size up to 1 MiB. Kept so nothing that imported before is refused now.
    public var lenientExtensions: Set<String> {
        layout == .batteryFile && system != .n64 ? extensions.union(Self.legacyExtensions) : extensions
    }
    public let lenientSizeRanges: [ClosedRange<Int>]

    /// Folder names other emulators keep these saves in (RetroArch's per-core `saves/<core>/`,
    /// standalone apps), lower case. A hint when a save's name fits games on two systems.
    public let folderHints: Set<String>

    public func acceptsSize(_ bytes: Int) -> Bool {
        sizes.contains(bytes) || sizeRanges.contains { $0.contains(bytes) }
    }

    public func accepts(extension ext: String, size bytes: Int) -> Bool {
        extensions.contains(ext.lowercased()) && acceptsSize(bytes)
    }

    public func acceptsLeniently(extension ext: String, size bytes: Int) -> Bool {
        lenientExtensions.contains(ext.lowercased())
            && (acceptsSize(bytes) || lenientSizeRanges.contains { $0.contains(bytes) })
    }

    /// The extensions the in-game import took for every system before this table.
    static let legacyExtensions: Set<String> = ["sav", "srm", "eep", "fla", "sra", "mpk", "mcr"]

    /// Where `game`'s save lives in the sandbox (the SAVEDATA root for PSP).
    public func destination(for game: LibraryGame, paths: SavePaths) -> URL {
        switch system {
        case .n64:
            return paths.n64SRAMURL(forRelativeROMPath: game.relativePath)
        case .psp:
            return paths.pspSavedataDirectory
        case .gba, .nds, .nes, .snes, .genesis, .atari7800, .ps1:
            return paths.sramURL(forRelativeROMPath: game.relativePath)
        }
    }

    public static func of(_ system: SystemID) -> SaveFormat {
        all[system]!
    }

    /// Every extension some core reads as a battery save.
    public static let batteryExtensions: Set<String> = all.values.reduce(into: []) {
        $0.formUnion($1.extensions)
        $0.formUnion($1.unusableExtensions.keys)
    }

    /// Mupen64Plus-Next keeps EEPROM, four Controller Paks, SRAM and FlashRAM in one block.
    public static let n64CombinedSRMSize = 0x800 + 4 * 0x8000 + 0x8000 + 0x20000

    /// The libretro cores keep one SAVE_RAM block whose size depends on the cartridge; only
    /// empty or absurd files are refused.
    private static let cartridgeRange = [1...(1 << 20)]

    private static let n64PackHint =
        "must be packed into a 290 KiB Mupen64Plus-Next .srm (RetroArch export or ra_mp64_srm_convert) before importing."

    public static let all: [SystemID: SaveFormat] = {
        let formats = [
            SaveFormat(
                system: .gba, layout: .batteryFile,
                extensions: ["sav", "srm"],
                // SRAM, EEPROM, Flash; mGBA may append a 16-byte RTC block.
                sizes: [512, 8_192, 32_768, 65_536, 131_072, 136_192, 137_216],
                sizeRanges: [131_073...(131_072 + 16_384)],
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["mgba", "gpsp", "vba-m", "vba next", "vbam", "meteor", "gba"]
            ),
            SaveFormat(
                system: .n64, layout: .batteryFile,
                extensions: ["srm"],
                sizes: [n64CombinedSRMSize],
                sizeRanges: [],
                unusableExtensions: [
                    "eep": "Loose .eep files \(n64PackHint)",
                    "sra": "Loose .sra files \(n64PackHint)",
                    "fla": "Loose .fla files \(n64PackHint)",
                    "mpk": "Loose .mpk files \(n64PackHint)",
                ],
                lenientSizeRanges: [],
                folderHints: ["mupen64plus-next", "mupen64plus", "parallel n64", "parallel-n64", "n64"]
            ),
            SaveFormat(
                system: .nds, layout: .batteryFile,
                // melonDS writes .sav; RetroArch's melonDS core .srm.
                extensions: ["sav", "srm"],
                sizes: [512, 8_192, 65_536, 131_072, 262_144, 524_288, 1_048_576, 8_388_608, 33_554_432],
                sizeRanges: [],
                unusableExtensions: [
                    "dsv": "DeSmuME .dsv saves carry a footer; export a raw .sav from DeSmuME first.",
                ],
                lenientSizeRanges: [],
                folderHints: ["melonds", "desmume", "nds"]
            ),
            SaveFormat(
                system: .psp, layout: .pspSavedataFolders,
                extensions: [], sizes: [], sizeRanges: [],
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["ppsspp", "psp", "savedata"]
            ),
            SaveFormat(
                system: .nes, layout: .batteryFile,
                extensions: ["sav", "srm"], sizes: [], sizeRanges: cartridgeRange,
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["nestopia", "nestopia ue", "fceumm", "mesen", "quicknes", "nes"]
            ),
            SaveFormat(
                system: .snes, layout: .batteryFile,
                extensions: ["sav", "srm"], sizes: [], sizeRanges: cartridgeRange,
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["bsnes", "snes9x", "snes9x2010", "mesen-s", "snes"]
            ),
            SaveFormat(
                system: .genesis, layout: .batteryFile,
                extensions: ["sav", "srm"], sizes: [], sizeRanges: cartridgeRange,
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["genesis plus gx", "picodrive", "blastem", "clownmdemu", "genesis", "megadrive", "md"]
            ),
            SaveFormat(
                system: .atari7800, layout: .batteryFile,
                extensions: ["sav", "srm"], sizes: [], sizeRanges: cartridgeRange,
                unusableExtensions: [:],
                lenientSizeRanges: [],
                folderHints: ["prosystem", "a7800", "atari7800", "atari 7800"]
            ),
            SaveFormat(
                system: .ps1, layout: .batteryFile,
                // PCSX-ReARMed's SAVE_RAM is memory card 1: a raw 128 KiB card, the format
                // RetroPlay (.sav), RetroArch (.srm), ePSXe (.mcr) and DuckStation (.mcd) write.
                extensions: ["sav", "srm", "mcr", "mcd"],
                sizes: [131_072],
                sizeRanges: [],
                unusableExtensions: [
                    "gme": "DexDrive .gme cards carry a header; convert to a raw .mcr first.",
                    "vmp": "PS3 .vmp cards are signed; convert to a raw .mcr first.",
                ],
                // The in-game import took any size up to 1 MiB.
                lenientSizeRanges: cartridgeRange,
                folderHints: ["pcsx-rearmed", "pcsx_rearmed", "beetle psx", "beetle psx hw", "mednafen psx", "swanstation", "duckstation", "epsxe", "ps1", "psx", "memcards"]
            ),
        ]
        return Dictionary(uniqueKeysWithValues: formats.map { ($0.system, $0) })
    }()
}

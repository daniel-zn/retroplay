// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Every core's battery saves, as other emulators leave them (docs/SAVES.md): imported from
/// the library by name, with and without region tags, and installed at the path that core
/// boots from (`SavePaths.batterySaveURL(system:romURL:)`, which the drivers load). Bytes are
/// synthetic; names and folder layouts are the real ones.
final class SaveFormatPerCoreTests: XCTestCase {
    private struct Row {
        let system: SystemID
        /// The ROM's file name in the library.
        let rom: String
        /// The save, as picked (folders included).
        let save: String
        let size: Int
        /// nil: imported. Otherwise a word the reason it's refused must contain.
        var refused: String?
        /// The pause menu's import still takes it (its wider, older rules).
        var inGameTakesIt = false
        let line: UInt

        init(
            _ system: SystemID, _ rom: String, _ save: String, _ size: Int,
            refused: String? = nil, inGameTakesIt: Bool = false, line: UInt = #line
        ) {
            self.system = system
            self.rom = rom
            self.save = save
            self.size = size
            self.refused = refused
            self.inGameTakesIt = inGameTakesIt
            self.line = line
        }
    }

    private static let gba: [Row] = [
        Row(.gba, "Pac-Man.gba", "RetroArch/saves/mGBA/Pac-Man (USA, Europe).srm", 8_192),   // EEPROM 64K
        Row(.gba, "Pac-Man (USA, Europe).gba", "mGBA/Pac-Man (USA, Europe).sav", 512),       // EEPROM 4K
        Row(.gba, "Mario Advance 4 (USA).gba", "Delta/Mario Advance 4.sav", 131_072),         // Flash 128K
        Row(.gba, "Golden Sun (USA).gba", "OpenEmu/mGBA/Battery Saves/Golden Sun (USA).sav", 65_536), // Flash 64K
        Row(.gba, "Advance Wars (USA).gba", "VBA-M/Advance Wars (USA).sav", 32_768),          // SRAM
        Row(.gba, "Pokemon Ruby (USA).gba", "mGBA/Pokemon Ruby (USA).sav", 131_088),          // Flash + mGBA RTC
        Row(.gba, "Pac-Man.gba", "mGBA/Pac-Man.sav", 1_000, refused: "size"),
    ]

    private static let nds: [Row] = [
        Row(.nds, "Mario Kart DS (USA).nds", "melonDS/Mario Kart DS (USA).sav", 524_288),
        Row(.nds, "Mario Kart DS.nds", "RetroArch/saves/melonDS/Mario Kart DS (USA, Europe).srm", 524_288),
        Row(.nds, "Picross DS (USA).nds", "Delta/Picross DS.sav", 8_192),
        Row(.nds, "Mario Kart DS.nds", "DeSmuME/Mario Kart DS.dsv", 524_410, refused: "DeSmuME"),
    ]

    private static let n64: [Row] = [
        Row(.n64, "Super Mario 64 (USA).z64", "RetroArch/saves/Mupen64Plus-Next/Super Mario 64 (USA).srm", SaveFormat.n64CombinedSRMSize),
        Row(.n64, "Super Mario 64.z64", "RetroArch/saves/Mupen64Plus-Next/Super Mario 64 (USA).srm", SaveFormat.n64CombinedSRMSize),
    ]

    private static let nes: [Row] = [
        Row(.nes, "Zelda (USA).nes", "RetroArch/saves/Nestopia/Zelda (USA).srm", 8_192),
        Row(.nes, "Zelda.nes", "FCEUX/sav/Zelda (USA) (Rev 1).sav", 8_192),
        Row(.nes, "Zelda (USA).nes", "Mesen/Saves/Zelda.sav", 8_192),
        Row(.nes, "Zelda (USA).nes", "OpenEmu/Nestopia/Battery Saves/Zelda (USA).sav", 8_192),
    ]

    private static let snes: [Row] = [
        Row(.snes, "Chrono Trigger (USA).sfc", "Snes9x/Saves/Chrono Trigger (USA).srm", 8_192),
        Row(.snes, "Chrono Trigger.sfc", "RetroArch/saves/bsnes/Chrono Trigger (USA).srm", 8_192),
        Row(.snes, "Super Mario World (USA).sfc", "Delta/Super Mario World.srm", 2_048),
        Row(.snes, "Super Mario World (USA).smc", "OpenEmu/SNES9x/Battery Saves/Super Mario World (USA).sav", 2_048),
    ]

    private static let genesis: [Row] = [
        // Genesis Plus GX / RetroArch keep the whole 64 KiB SRAM window, odd-byte saves too.
        Row(.genesis, "Phantasy Star IV (USA).md", "RetroArch/saves/Genesis Plus GX/Phantasy Star IV (USA).srm", 65_536),
        Row(.genesis, "Sonic 3.bin", "OpenEmu/Genesis Plus/Battery Saves/Sonic 3 (USA).sav", 65_536),
        Row(.genesis, "Shining Force (USA).md", "BlastEm/Shining Force (USA).sav", 16_384),
        // Bigger than the core's 64 KiB window: it would be cut off.
        Row(.genesis, "Phantasy Star IV (USA).md", "Genesis/Phantasy Star IV (USA).srm", 131_072, refused: "size"),
    ]

    private static let atari7800: [Row] = [
        // ProSystem keeps no battery save: only save states.
        Row(.atari7800, "Asteroids (USA).a78", "RetroArch/saves/ProSystem/Asteroids (USA).srm", 8_192, refused: "save states"),
    ]

    private static let ps1: [Row] = [
        Row(.ps1, "Final Fantasy VII (USA).cue", "RetroArch/saves/PCSX-ReARMed/Final Fantasy VII (USA).srm", 131_072),
        Row(.ps1, "Final Fantasy VII.cue", "DuckStation/memcards/Final Fantasy VII (USA)_1.mcd", 131_072),
        Row(.ps1, "Final Fantasy VII (USA).chd", "ePSXe/memcards/Final Fantasy VII (USA).mcr", 131_072),
        Row(.ps1, "Final Fantasy VII (USA).cue", "DexDrive/Final Fantasy VII (USA).gme", 131_200, refused: "DexDrive"),
        Row(.ps1, "Final Fantasy VII (USA).cue", "RetroArch/saves/PCSX-ReARMed/Final Fantasy VII (USA).srm", 65_536, refused: "size", inGameTakesIt: true),
    ]

    func testGBA() throws { try check(Self.gba) }
    func testNDS() throws { try check(Self.nds) }
    func testN64() throws { try check(Self.n64) }
    func testNES() throws { try check(Self.nes) }
    func testSNES() throws { try check(Self.snes) }
    func testGenesis() throws { try check(Self.genesis) }
    func testAtari7800() throws { try check(Self.atari7800) }
    func testPS1() throws { try check(Self.ps1) }

    func testEveryCoreHasRows() {
        let covered = Set((Self.gba + Self.nds + Self.n64 + Self.nes + Self.snes + Self.genesis + Self.atari7800 + Self.ps1).map(\.system))
        // PSP saves are SAVEDATA folders, covered by the PSP import tests.
        XCTAssertEqual(covered.union([.psp]), Set(SystemID.allCases))
    }

    func testPSPSlotInstallsWherePPSSPPReadsIt() throws {
        try withSandbox { pick, paths in
            let slot = pick.appendingPathComponent("PPSSPP/PSP/SAVEDATA/ULUS10041DATA00", isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try Data("PSF".utf8).write(to: slot.appendingPathComponent("PARAM.SFO"))
            try Data("DATA".utf8).write(to: slot.appendingPathComponent("DATA.BIN"))
            let game = LibraryGame(displayName: "Game", systemID: .psp, relativePath: "Game (USA).iso", pspProductID: "ULUS10041")

            let batch = LibrarySaveImporter().plan(SaveFolderScanner.scan([pick]), games: [game], paths: paths)
            let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths)

            XCTAssertEqual(outcome.imported.count, 1, "\(batch.skipped) \(outcome.failed)")
            let installed = paths.pspSavedataDirectory.appendingPathComponent("ULUS10041DATA00/DATA.BIN")
            XCTAssertEqual(try Data(contentsOf: installed), Data("DATA".utf8))
        }
    }

    // MARK: Harness

    private func withSandbox(_ body: (URL, SavePaths) throws -> Void) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-per-core-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let pick = root.appendingPathComponent("Pick", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        let paths = SavePaths(fileManager: fm, documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories(fileManager: fm)
        try body(pick, paths)
    }

    private func check(_ rows: [Row]) throws {
        for row in rows {
            try withSandbox { pick, paths in
                let source = pick.appendingPathComponent(row.save)
                try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                let bytes = Data((0..<row.size).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) })
                try bytes.write(to: source)
                let game = LibraryGame(
                    displayName: (row.rom as NSString).deletingPathExtension,
                    systemID: row.system,
                    relativePath: row.rom
                )

                let batch = LibrarySaveImporter().plan(SaveFolderScanner.scan([pick]), games: [game], paths: paths)
                let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths)

                let bootPath = paths.batterySaveURL(system: row.system, romURL: paths.gameROMURL(forRelativePath: row.rom))
                if let refused = row.refused {
                    XCTAssertTrue(batch.items.isEmpty, "\(row.save) should be refused", line: row.line)
                    let reason = batch.skipped.first?.reason ?? ""
                    XCTAssertTrue(reason.localizedCaseInsensitiveContains(refused), "\(row.save): \(reason)", line: row.line)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: bootPath.path), line: row.line)
                    // The in-game import refuses it too.
                    if !row.inGameTakesIt {
                        XCTAssertThrowsError(try SaveGameImporter().planImport(from: source, for: game, paths: paths), line: row.line)
                    }
                    return
                }
                XCTAssertEqual(outcome.imported.map(\.game.id), [game.id], "\(row.save): \(batch.skipped) \(outcome.failed)", line: row.line)
                XCTAssertEqual(try? Data(contentsOf: bootPath), bytes, "\(row.save) not at \(bootPath.path)", line: row.line)

                // The pause menu's import takes the same file for the same game.
                try FileManager.default.removeItem(at: bootPath)
                let plan = try SaveGameImporter().planImport(from: source, for: game, paths: paths)
                XCTAssertEqual(plan.destinationURL, bootPath, line: row.line)
            }
        }
    }
}

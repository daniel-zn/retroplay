// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Save folders as real games and backup tools name them: PSP save names with '-' and mixed
/// case (kept as the game wrote them: PPSSPP's save lists compare names case-sensitively),
/// folders with PARAM.SFO that still can't be used, and trees from systems RetroPlay doesn't
/// play (Wii U, PS Vita).
final class SaveImportRealFoldersTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var pick: URL!
    private var paths: SavePaths!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-real-\(UUID().uuidString)", isDirectory: true)
        pick = root.appendingPathComponent("Game Saves", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String, count: Int = 8_192, fill: UInt8 = 7) throws -> URL {
        let url = pick.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: count).write(to: url)
        return url
    }

    private func pspSave(_ path: String, fill: UInt8 = 7) throws {
        try write("\(path)/PARAM.SFO", count: 3, fill: fill)
        try write("\(path)/DATA.BIN", count: 16, fill: fill)
    }

    private func psp(_ name: String, _ id: String) -> LibraryGame {
        LibraryGame(displayName: name, systemID: .psp, relativePath: "\(name).iso", pspProductID: id)
    }

    private func plan(_ games: [LibraryGame]) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([pick]), games: games, paths: paths)
    }

    private func savedataNames() throws -> [String] {
        try fm.contentsOfDirectory(atPath: paths.pspSavedataDirectory.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    func testPSPSaveNameWithADashIsImported() throws {
        try pspSave("PSP/Gran Turismo/2026-10-30/UCUS98632-GAMEDAT")
        let batch = plan([psp("Gran Turismo", "UCUS98632")])
        XCTAssertEqual(batch.items.map(\.plan.destinationURL.lastPathComponent), ["UCUS98632-GAMEDAT"], "\(batch.skipped)")
    }

    func testPSPFoldersAreInstalledUnderTheGamesOwnName() throws {
        try pspSave("PSP/FF4/ULUS10560System")
        try pspSave("PSP/Uncharted/UCUS98731_GameData0")
        try pspSave("PSP/Ben 10/ULUS10387Ben101")
        let games = [psp("FF4", "ULUS10560"), psp("Uncharted", "UCUS98731"), psp("Ben 10", "ULUS10387")]

        let outcome = LibrarySaveImporter().commit(plan(games), replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.imported.count, 3, "\(outcome.failed)")
        XCTAssertEqual(try savedataNames(), ["UCUS98731_GameData0", "ULUS10387Ben101", "ULUS10560System"])
    }

    func testReimportGivesAnUppercasedEarlierImportItsOwnName() throws {
        // What an earlier build installed: the name upper-cased.
        let old = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560SYSTEM", isDirectory: true)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: old.appendingPathComponent("PARAM.SFO"))
        try pspSave("ULUS10560System", fill: 9)

        let batch = plan([psp("FF4", "ULUS10560")])
        XCTAssertEqual(batch.replacements.count, 1)
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        XCTAssertEqual(try savedataNames(), ["ULUS10560System"])
        let param = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560System/PARAM.SFO")
        XCTAssertEqual(try Data(contentsOf: param), Data(repeating: 9, count: 3))
    }

    func testAllLowerCaseCopyGetsTheUpperCaseNameBack() throws {
        try pspSave("ucus98737data00")
        let outcome = LibrarySaveImporter().commit(plan([psp("God of War", "UCUS98737")]), replaceExisting: true, paths: paths)
        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertEqual(try savedataNames(), ["UCUS98737DATA00"])
    }

    func testFolderWithPARAMSFOThatCanNotBeUsedIsReported() throws {
        try pspSave("PSP/Homebrew/MYSAVE")
        let batch = plan([psp("Gran Turismo", "UCUS98632")])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertNotNil(batch.skipped.first { $0.name.hasSuffix("MYSAVE") }, "\(batch.skipped), ignored \(batch.ignoredFiles)")
    }

    func testSavesFromOtherSystemsAreNotBlamedOnTheLibrary() throws {
        try write("Wii U/Breath of the Wild/2024-07-20/80000001/option.sav", count: 1_024)
        try write("Wii U/Breath of the Wild/2024-07-20/80000001/4/game_data.sav", count: 4_096)
        try write("PSVita/LittleBigPlanet Vita/2026-10-30/PCSA00017/sce_sys/param.sfo", count: 3)
        try write("PSVita/Dungeon Hunter/PCSE00383/save.sav", count: 4_096)
        let gba = LibraryGame(displayName: "Zelda", systemID: .gba, relativePath: "Zelda.gba")

        let batch = plan([gba])

        // Counted in one line of the summary, not listed: one per Wii U account folder, Vita
        // save, and file inside a Vita title folder.
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(batch.otherSystemSaves, 3)
    }

    func testFileNoRetroPlaySystemCouldReadSaysSo() throws {
        // A .sav no system's sizes fit (2 MiB).
        try write("Random/thing.sav", count: 2 << 20)
        let batch = plan([LibraryGame(displayName: "Zelda", systemID: .gba, relativePath: "Zelda.gba")])
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(batch.otherSystemSaves, 1)
    }

    func testOtherSystemsSavesAddUpAcrossABackupTree() throws {
        for game in ["PCSA00017", "PCSE00383", "PCSE00790"] {
            try write("PSVita/\(game)/sce_sys/param.sfo", count: 3)
        }
        try write("Wii U/BotW/80000001/option.sav", count: 1_024)
        try pspSave("PSP/Gran Turismo/UCUS98632-GAMEDAT")

        let batch = plan([psp("Gran Turismo", "UCUS98632")])

        XCTAssertEqual(batch.items.count, 1)
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(batch.otherSystemSaves, 4)
    }
}

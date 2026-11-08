// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Saves imported before their game: kept under their own names, listed for Settings, and
/// attached to the game (shown in its pause menu) once it's added. Names follow the layout a
/// save backup really has (`GBA/<game>/<date>/<No-Intro name>.srm`); the bytes are synthetic.
@MainActor
final class KeptSavesTests: XCTestCase {
    private var root: URL!
    private var pick: URL!
    private var documents: URL!
    private var paths: SavePaths!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-kept-saves-\(UUID().uuidString)", isDirectory: true)
        pick = root.appendingPathComponent("Pick", isDirectory: true)
        documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        paths = SavePaths(fileManager: fm, documentsURL: documents)
        try paths.ensureDirectories(fileManager: fm)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    /// An 8 KiB GBA EEPROM as mGBA writes it: erased (0xFF) but for the game's few bytes.
    private func eeprom() -> Data {
        var data = Data(repeating: 0xFF, count: 8_192)
        data.replaceSubrange(8_176..<8_192, with: Data((0..<16).map { UInt8($0) }))
        return data
    }

    @discardableResult
    private func write(_ relative: String, _ data: Data) throws -> URL {
        let url = pick.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private func importSaves(games: [LibraryGame]) -> (SaveImportBatch, SaveImportOutcome) {
        let batch = LibrarySaveImporter().plan(SaveFolderScanner.scan([pick], fileManager: fm), games: games, paths: paths, fileManager: fm)
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)
        return (batch, outcome)
    }

    private func addGame(_ fileName: String) throws -> (LibraryStore, LibraryGame) {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents)
        let rom = root.appendingPathComponent("Inbox", isDirectory: true).appendingPathComponent(fileName)
        try fm.createDirectory(at: rom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic test rom".utf8).write(to: rom)
        let game = try XCTUnwrap(try store.importFiles(from: [rom]).first)
        return (store, game)
    }

    // MARK: In-game import

    func testInGameImportTakesTheSaveUnderItsFullNoIntroName() throws {
        let save = try write("Classic NES Series - Pac-Man (USA, Europe).srm", eeprom())
        let game = LibraryGame(displayName: "Pac-Man", systemID: .gba, relativePath: "Classic NES Series - Pac-Man.gba")

        let plan = try SaveGameImporter().planImport(from: save, for: game, paths: paths, fileManager: fm)

        XCTAssertEqual(plan.destinationURL, paths.batterySaveURL(for: game))
    }

    func testInGameImportStillRefusesAnotherGamesSave() throws {
        let save = try write("Classic NES Series - Donkey Kong (USA, Europe).srm", eeprom())
        let game = LibraryGame(displayName: "Pac-Man", systemID: .gba, relativePath: "Classic NES Series - Pac-Man.gba")

        XCTAssertThrowsError(try SaveGameImporter().planImport(from: save, for: game, paths: paths, fileManager: fm))
    }

    // MARK: Kept until the game is added

    func testSaveForAGameNotInTheLibraryIsKeptAndListed() throws {
        try write("GBA/Classic NES Series - Pac-Man/2026-10-30/Classic NES Series - Pac-Man (USA, Europe).srm", eeprom())

        let (batch, outcome) = importSaves(games: [])

        XCTAssertEqual(batch.forMissingGames.count, 1, "\(batch.skipped)")
        XCTAssertEqual(batch.forMissingGames.first?.game.systemID, .gba)
        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        let kept = KeptSaves.list(games: [], paths: paths, fileManager: fm)
        XCTAssertEqual(kept.map(\.title), ["Classic NES Series - Pac-Man (USA, Europe)"])
        XCTAssertEqual(kept.first?.system, .gba)
        XCTAssertEqual(kept.first?.bytes, 8_192)
    }

    func testKeptSaveAttachesWhenItsGameIsAddedAndShowsInThePauseMenu() throws {
        try write("GBA/Classic NES Series - Pac-Man/2026-10-30/Classic NES Series - Pac-Man (USA, Europe).srm", eeprom())
        _ = importSaves(games: [])

        let (store, game) = try addGame("Classic NES Series - Pac-Man.gba")

        let installed = paths.batterySaveURL(system: .gba, romURL: store.absoluteURL(for: game))
        XCTAssertEqual(try Data(contentsOf: installed), eeprom())
        XCTAssertNotNil(InGameSave.lastSaved(for: game, paths: paths, fileManager: fm))
        XCTAssertTrue(KeptSaves.list(games: store.games, paths: paths, fileManager: fm).isEmpty)
    }

    func testKeptSaveIsNotAttachedToAnotherGame() throws {
        try write("GBA/Classic NES Series - Pac-Man (USA, Europe).srm", eeprom())
        _ = importSaves(games: [])

        let (_, game) = try addGame("Classic NES Series - Donkey Kong.gba")

        XCTAssertNil(InGameSave.lastSaved(for: game, paths: paths, fileManager: fm))
        XCTAssertEqual(KeptSaves.list(games: [game], paths: paths, fileManager: fm).count, 1)
    }

    func testKeptSaveDoesNotReplaceTheGamesOwnSave() throws {
        try write("GBA/Pac-Man (USA).srm", eeprom())
        _ = importSaves(games: [])
        let own = paths.sramURL(forRelativeROMPath: "Pac-Man.gba")
        try Data(repeating: 0x11, count: 8_192).write(to: own)

        _ = try addGame("Pac-Man.gba")

        XCTAssertEqual(try Data(contentsOf: own), Data(repeating: 0x11, count: 8_192))
        XCTAssertEqual(KeptSaves.list(games: [], paths: paths, fileManager: fm).count, 1)
    }

    func testSaveWithNoSystemHintIsSkippedWithAReason() throws {
        try write("Some Game.srm", Data(repeating: 0, count: 8_192))

        let (batch, _) = importSaves(games: [])

        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(batch.skipped.first?.reason).contains("which system"))
    }

    func testDeletingAKeptSave() throws {
        try write("SNES/Chrono Trigger (USA).srm", Data(repeating: 0, count: 8_192))
        _ = importSaves(games: [])
        let kept = try XCTUnwrap(KeptSaves.list(games: [], paths: paths, fileManager: fm).first)
        XCTAssertEqual(kept.system, .snes)

        try KeptSaves.delete(kept, fileManager: fm)

        XCTAssertTrue(KeptSaves.list(games: [], paths: paths, fileManager: fm).isEmpty)
    }

    // MARK: PSP

    /// A PARAM.SFO with TITLE and SAVEDATA_DIRECTORY, as a PSP save slot has.
    private func paramSFO(title: String, directory: String) -> Data {
        let entries: [(String, Data)] = [
            ("SAVEDATA_DIRECTORY", Data(directory.utf8) + Data([0])),
            ("TITLE", Data(title.utf8) + Data([0])),
        ]
        var keys = Data()
        var values = Data()
        var table = Data()
        for (key, value) in entries {
            func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
            func le32(_ v: Int) -> Data { Data((0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) }) }
            table += le16(keys.count) + Data([0x04, 0x02]) + le32(value.count) + le32(value.count) + le32(values.count)
            keys += Data(key.utf8) + Data([0])
            values += value
        }
        while keys.count % 4 != 0 { keys.append(0) }
        func le32(_ v: Int) -> Data { Data((0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) }) }
        let keyOffset = 20 + table.count
        let valueOffset = keyOffset + keys.count
        return Data([0x00, 0x50, 0x53, 0x46, 0x01, 0x01, 0x00, 0x00])
            + le32(keyOffset) + le32(valueOffset) + le32(entries.count) + table + keys + values
    }

    func testKeptPSPSaveIsListedByItsTitleAndShowsForItsGame() throws {
        let slot = pick.appendingPathComponent("SAVEDATA/ULUS10041DATA00", isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        try paramSFO(title: "Test Game", directory: "ULUS10041DATA00").write(to: slot.appendingPathComponent("PARAM.SFO"))
        try Data("DATA".utf8).write(to: slot.appendingPathComponent("DATA.BIN"))

        let (batch, outcome) = importSaves(games: [])
        XCTAssertEqual(batch.forMissingGames.count, 1, "\(batch.skipped)")
        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        XCTAssertEqual(KeptSaves.list(games: [], paths: paths, fileManager: fm).map(\.title), ["Test Game"])

        let game = LibraryGame(displayName: "Test Game", systemID: .psp, relativePath: "Test Game.iso", pspProductID: "ULUS10041")
        XCTAssertNotNil(InGameSave.lastSaved(for: game, paths: paths, fileManager: fm))
        XCTAssertTrue(KeptSaves.list(games: [game], paths: paths, fileManager: fm).isEmpty)
    }
}

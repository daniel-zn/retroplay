// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class SavePathsTests: XCTestCase {
    func testSRAMAndStateURLsPreserveRelativeFolders() {
        let paths = SavePaths(fileManager: .default)
        let sram = paths.sramURL(forRelativeROMPath: "Pocket/demo.gba")
        XCTAssertEqual(sram.pathExtension, "sav")
        XCTAssertTrue(sram.path.contains("/Saves/"))
        XCTAssertTrue(sram.path.hasSuffix("Pocket/demo.sav"))

        let state = paths.stateURL(forRelativeROMPath: "demo.gba", slot: 2)
        XCTAssertTrue(state.path.contains("/States/"))
        XCTAssertEqual(state.lastPathComponent, "demo.slot2.state")
    }

    func testDocumentsTreeUsesGamesNotROMs() {
        let paths = SavePaths(fileManager: .default)
        XCTAssertTrue(paths.gamesDirectory.path.hasSuffix("/Games"))
        XCTAssertEqual(paths.romsDirectory, paths.gamesDirectory)
        XCTAssertTrue(paths.savesDirectory.path.hasSuffix("/Saves"))
        XCTAssertTrue(paths.statesDirectory.path.hasSuffix("/States"))
        XCTAssertTrue(paths.cheatsDirectory.path.hasSuffix("/Cheats"))
        XCTAssertTrue(paths.pspMemstickDirectory.path.contains("/Saves/psp"))
        XCTAssertTrue(paths.pspSavedataDirectory.path.hasSuffix("/PSP/SAVEDATA"))
    }

    func testN64SRAMURLUsesSavesN64Folder() {
        let paths = SavePaths(fileManager: .default)
        let url = paths.n64SRAMURL(forRelativeROMPath: "Mario Kart 64.z64")
        XCTAssertTrue(url.path.contains("/Saves/n64/"))
        XCTAssertEqual(url.lastPathComponent, "Mario Kart 64.srm")
    }

    func testRelativeROMPathFromAbsoluteURL() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-rel-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let rom = paths.gamesDirectory.appendingPathComponent("Pocket/demo.gba")
        XCTAssertEqual(paths.relativeROMPath(fromAbsoluteROMURL: rom), "Pocket/demo.gba")
        XCTAssertEqual(
            paths.sramURL(forRelativeROMPath: paths.relativeROMPath(fromAbsoluteROMURL: rom)).lastPathComponent,
            "demo.sav"
        )
    }

    func testSanitizedRelativePathRejectsParentHops() {
        XCTAssertNil(SavePaths.sanitizedRelativePath("../escape.gba"))
        XCTAssertNil(SavePaths.sanitizedRelativePath("Pocket/../../evil.gba"))
        XCTAssertEqual(SavePaths.sanitizedRelativePath("Pocket/demo.gba"), "Pocket/demo.gba")
        XCTAssertFalse(SavePaths.isSafeFileName("../evil.gba"))
        XCTAssertTrue(SavePaths.isSafeFileName("demo.gba"))
    }

    func testSRAMURLStaysInsideSavesWhenRelativePathHasParentHops() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-safe-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)

        let url = paths.sramURL(forRelativeROMPath: "../../outside.gba")
        XCTAssertTrue(url.path.hasPrefix(paths.savesDirectory.path))
        XCTAssertFalse(url.path.contains("/../"))
        XCTAssertEqual(url.lastPathComponent, "outside.sav")
    }

    func testGamesURLRejectsUnsafeRelativePaths() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-games-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)

        XCTAssertNil(paths.gamesURL(forRelativePath: "../secret.gba"))
        XCTAssertEqual(
            paths.gamesURL(forRelativePath: "Pocket/demo.gba")?.lastPathComponent,
            "demo.gba"
        )
    }

    func testQuickSaveLivesUnderStatesAndExistsDoesNotCreate() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-state-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let id = UUID()
        XCTAssertFalse(SaveStateStore.quickSaveExists(system: .gba, gameID: id, paths: paths))
        let dir = SaveStateStore.quickSaveDirectory(system: .gba, gameID: id, paths: paths)
        XCTAssertTrue(dir.path.contains("/States/gba/"))
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    func testMigrationMovesROMAdjacentGBASaveIntoSaves() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-sav-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let legacy = paths.gamesDirectory.appendingPathComponent("Mario.sav")
        try Data("sram".utf8).write(to: legacy)

        try paths.migrateLegacyLayout(fileManager: fm)

        let moved = paths.sramURL(forRelativeROMPath: "Mario.gba")
        XCTAssertEqual(try Data(contentsOf: moved), Data("sram".utf8))
        XCTAssertFalse(fm.fileExists(atPath: legacy.path))
    }

    func testMigrationKeepsExistingSaveOverROMAdjacentCopy() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-sav-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        try Data("old".utf8).write(to: paths.gamesDirectory.appendingPathComponent("Mario.sav"))
        let current = paths.sramURL(forRelativeROMPath: "Mario.gba")
        try Data("new".utf8).write(to: current)

        try paths.migrateLegacyLayout(fileManager: fm)

        XCTAssertEqual(try Data(contentsOf: current), Data("new".utf8))
    }

    /// PPSSPP's GetSysDirectory strips a memstick folder named "PSP" (strcasecmp).
    func testMemstickFolderIsNotNamedPSPInAnyCase() {
        let name = SavePaths().pspMemstickDirectory.lastPathComponent
        XCTAssertNotEqual(name.lowercased(), "psp")
    }

    func testMigrationMovesSavedataFromOldPSPMemstick() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-psp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let old = paths.savesDirectory.appendingPathComponent("psp", isDirectory: true)
        let gameSide = old.appendingPathComponent("PSP/SAVEDATA/ULUS10000DATA", isDirectory: true)
        let ppssppSide = old.appendingPathComponent("SAVEDATA/UCUS98648PROFILE00", isDirectory: true)
        for dir in [gameSide, ppssppSide] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("save".utf8).write(to: dir.appendingPathComponent("DATA.BIN"))
        }

        try paths.migrateLegacyLayout(fileManager: fm)

        for name in ["ULUS10000DATA", "UCUS98648PROFILE00"] {
            let moved = paths.pspSavedataDirectory.appendingPathComponent(name).appendingPathComponent("DATA.BIN")
            XCTAssertTrue(fm.fileExists(atPath: moved.path), name)
        }
    }
}

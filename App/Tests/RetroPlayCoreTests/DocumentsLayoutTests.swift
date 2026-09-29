// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class DocumentsLayoutTests: XCTestCase {
    func testMigrateMovesROMsAndLegacyQuickStates() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-layout-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let oldROMs = root.appendingPathComponent("ROMs", isDirectory: true)
        try fm.createDirectory(at: oldROMs, withIntermediateDirectories: true)
        let rom = oldROMs.appendingPathComponent("pocket.gba")
        try Data("rom".utf8).write(to: rom)

        let gameID = UUID()
        let oldQuickDir = root
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent("gba", isDirectory: true)
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
        try fm.createDirectory(at: oldQuickDir, withIntermediateDirectories: true)
        let oldQuick = oldQuickDir.appendingPathComponent("quick.state")
        try Data([0x01]).write(to: oldQuick)

        let oldSRAM = root.appendingPathComponent("Saves", isDirectory: true).appendingPathComponent("pocket.sav")
        try Data([0x02]).write(to: oldSRAM)

        let oldN64 = root.appendingPathComponent("N64Saves", isDirectory: true)
        try fm.createDirectory(at: oldN64, withIntermediateDirectories: true)
        try Data([0x03]).write(to: oldN64.appendingPathComponent("cart.eep"))

        let oldPSP = root.appendingPathComponent("PPSSPP", isDirectory: true)
        try fm.createDirectory(at: oldPSP, withIntermediateDirectories: true)
        try Data([0x04]).write(to: oldPSP.appendingPathComponent("ppsspp.ini"))

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.migrateLegacyLayout(fileManager: fm)
        try paths.ensureDirectories(fileManager: fm)

        XCTAssertTrue(fm.fileExists(atPath: paths.gamesDirectory.appendingPathComponent("pocket.gba").path))
        XCTAssertFalse(fm.fileExists(atPath: oldROMs.path))
        XCTAssertTrue(fm.fileExists(atPath: oldSRAM.path), "SRAM stays under Saves/")
        XCTAssertTrue(
            fm.fileExists(
                atPath: paths.statesDirectory
                    .appendingPathComponent("gba", isDirectory: true)
                    .appendingPathComponent(gameID.uuidString, isDirectory: true)
                    .appendingPathComponent("quick.state").path
            )
        )
        XCTAssertFalse(fm.fileExists(atPath: oldQuick.path))
        XCTAssertTrue(fm.fileExists(atPath: paths.n64SavesDirectory.appendingPathComponent("cart.eep").path))
        XCTAssertTrue(fm.fileExists(atPath: paths.pspMemstickDirectory.appendingPathComponent("ppsspp.ini").path))
        XCTAssertTrue(fm.fileExists(atPath: paths.cheatsDirectory.path))
    }
}

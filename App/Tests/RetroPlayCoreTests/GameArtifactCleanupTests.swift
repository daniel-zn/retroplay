// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class GameArtifactCleanupTests: XCTestCase {
    func testRemoveUsesSanitizedROMPathNotParentTraversal() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-cleanup-safe-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let safeROM = paths.gameROMURL(forRelativePath: "../outside.gba")
        try fm.createDirectory(at: safeROM.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("rom".utf8).write(to: safeROM)

        let outside = root.appendingPathComponent("outside.gba")
        try Data("decoy".utf8).write(to: outside)

        let game = LibraryGame(displayName: "Evil", systemID: .gba, relativePath: "../outside.gba")
        try GameArtifactCleanup.removeArtifacts(for: game, paths: paths, fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: safeROM.path))
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
    }
}

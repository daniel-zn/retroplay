// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

@MainActor
final class LibraryStoreDeleteTests: XCTestCase {
    func testRemoveDeletesN64SRAMFromSavesN64Folder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-delete-n64-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let inbox = root.appendingPathComponent("inbox.z64")
        try Data("not-a-copyrighted-rom".utf8).write(to: inbox)

        let added = try store.importFiles(from: [inbox])
        let game = try XCTUnwrap(added.first)
        XCTAssertEqual(game.systemID, .n64)

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let srm = paths.n64SRAMURL(forRelativeROMPath: game.relativePath)
        try fm.createDirectory(at: srm.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xEE]).write(to: srm)

        try store.remove(game)

        XCTAssertFalse(fm.fileExists(atPath: srm.path))
    }

    func testAbsoluteURLBlocksParentHopsInStoredRelativePath() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-abs-safe-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let game = LibraryGame(displayName: "Evil", systemID: .gba, relativePath: "../outside.gba")
        let url = store.absoluteURL(for: game)

        XCTAssertTrue(url.path.hasPrefix(store.gamesDirectoryURL.path))
        XCTAssertEqual(url.lastPathComponent, "outside.gba")
    }

    func testRemovePersistsLibraryRemovalBeforeArtifactCleanup() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-delete-txn-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let inbox = root.appendingPathComponent("inbox.gba")
        try Data("not-a-copyrighted-rom".utf8).write(to: inbox)

        let added = try store.importFiles(from: [inbox])
        let game = try XCTUnwrap(added.first)

        let rom = store.absoluteURL(for: game)
        try fm.removeItem(at: rom)

        // A ROM already removed in Files counts as deleted; cleanup still succeeds.
        XCTAssertNoThrow(try store.remove(game))
        XCTAssertTrue(store.games.isEmpty)

        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertTrue(reloaded.games.isEmpty)
    }

    func testRemoveDeletesEvilRelativePathROMInsideGames() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-delete-evil-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let rom = paths.gameROMURL(forRelativePath: "../outside.gba")
        try fm.createDirectory(at: rom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("rom".utf8).write(to: rom)

        let outside = root.appendingPathComponent("outside.gba")
        try Data("decoy".utf8).write(to: outside)

        let game = LibraryGame(displayName: "Evil", systemID: .gba, relativePath: "../outside.gba")
        try GameArtifactCleanup.removeArtifacts(for: game, paths: paths, fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: rom.path))
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
    }

    func testRemoveDeletesLibraryRowROMAndRelatedArtifacts() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-delete-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let inbox = root.appendingPathComponent("inbox.gba")
        try Data("not-a-copyrighted-rom".utf8).write(to: inbox)

        let added = try store.importFiles(from: [inbox])
        XCTAssertEqual(added.count, 1)
        let game = try XCTUnwrap(added.first)
        XCTAssertEqual(store.games.count, 1)

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let rom = store.absoluteURL(for: game)
        XCTAssertTrue(rom.path.contains("/Games/"))
        XCTAssertTrue(fm.fileExists(atPath: rom.path))

        let sram = paths.sramURL(forRelativeROMPath: game.relativePath)
        try fm.createDirectory(at: sram.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xAA]).write(to: sram)

        let slot = paths.stateURL(forRelativeROMPath: game.relativePath, slot: 0)
        try fm.createDirectory(at: slot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xBB]).write(to: slot)

        let cheat = paths.cheatsDirectory.appendingPathComponent(
            ((game.relativePath as NSString).deletingPathExtension) + ".cht"
        )
        try fm.createDirectory(at: cheat.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cheat".utf8).write(to: cheat)

        let quick = try SaveStateStore.quickSaveURL(system: game.systemID, gameID: game.id, paths: paths)
        try Data([0xCC]).write(to: quick)

        let covers = CoverArtStore(fileManager: fm, documentsDirectoryURL: root)
        try covers.ensureDirectory()
        let cover = covers.coverURL(forGameID: game.id)
        try Data([0xDD]).write(to: cover)

        try store.remove(game)

        XCTAssertTrue(store.games.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: rom.path))
        XCTAssertFalse(fm.fileExists(atPath: sram.path))
        XCTAssertFalse(fm.fileExists(atPath: slot.path))
        XCTAssertFalse(fm.fileExists(atPath: cheat.path))
        XCTAssertFalse(fm.fileExists(atPath: quick.path))
        XCTAssertFalse(fm.fileExists(atPath: cover.path))

        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertTrue(reloaded.games.isEmpty)
    }
}

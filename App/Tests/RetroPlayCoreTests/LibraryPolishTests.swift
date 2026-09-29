// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Library import / delete / storage fixes: base-name collisions, missing-ROM delete, PSP
/// SAVEDATA ownership, malformed ISO sizes, app-data migration, duplicates, corrupt library.
@MainActor
final class LibraryPolishTests: XCTestCase {
    private let fm = FileManager.default
    private lazy var root: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-polish-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }()

    private func inboxFile(_ name: String, _ contents: String = "not-a-copyrighted-rom") throws -> URL {
        let dir = root.appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Base names across systems (2)

    func testImportAvoidsBaseNameUsedByAnotherSystem() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let gba = try XCTUnwrap(store.importFiles(from: [inboxFile("Game.gba", "gba")]).first)
        let nds = try XCTUnwrap(store.importFiles(from: [inboxFile("Game.nds", "nds")]).first)

        XCTAssertEqual(gba.relativePath, "Game.gba")
        XCTAssertEqual(nds.relativePath, "Game-1.nds")
        XCTAssertEqual(nds.displayName, "Game")

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        XCTAssertNotEqual(
            paths.sramURL(forRelativeROMPath: gba.relativePath),
            paths.sramURL(forRelativeROMPath: nds.relativePath)
        )
        XCTAssertNotEqual(
            paths.stateURL(forRelativeROMPath: gba.relativePath, slot: 0),
            paths.stateURL(forRelativeROMPath: nds.relativePath, slot: 0)
        )
    }

    func testSingleGameKeepsItsOriginalFileName() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let game = try XCTUnwrap(store.importFiles(from: [inboxFile("Zelda.gba")]).first)
        XCTAssertEqual(game.relativePath, "Zelda.gba")
    }

    func testCleanupKeepsSavesSharedWithAnotherRowsBaseName() throws {
        // Rows imported by older builds can already share a base name.
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let gba = LibraryGame(displayName: "Game", systemID: .gba, relativePath: "Game.gba")
        let nds = LibraryGame(displayName: "Game", systemID: .nds, relativePath: "Game.nds")
        for game in [gba, nds] {
            try Data("rom".utf8).write(to: paths.gameROMURL(forRelativePath: game.relativePath))
        }
        let sram = paths.sramURL(forRelativeROMPath: gba.relativePath)
        try Data([0xAA]).write(to: sram)
        let state = paths.stateURL(forRelativeROMPath: gba.relativePath, slot: 1)
        try Data([0xBB]).write(to: state)

        try GameArtifactCleanup.removeArtifacts(for: gba, paths: paths, otherGames: [nds], fileManager: fm)

        XCTAssertFalse(fm.fileExists(atPath: paths.gameROMURL(forRelativePath: gba.relativePath).path))
        XCTAssertTrue(fm.fileExists(atPath: paths.gameROMURL(forRelativePath: nds.relativePath).path))
        XCTAssertTrue(fm.fileExists(atPath: sram.path))
        XCTAssertTrue(fm.fileExists(atPath: state.path))
    }

    // MARK: - Missing ROM delete (3)

    func testRemoveWithMissingROMStillCleansArtifacts() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let game = try XCTUnwrap(store.importFiles(from: [inboxFile("Gone.gba")]).first)
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        let sram = paths.sramURL(forRelativeROMPath: game.relativePath)
        try Data([0xAA]).write(to: sram)
        let quick = try SaveStateStore.quickSaveURL(system: game.systemID, gameID: game.id, paths: paths)
        try Data([0xCC]).write(to: quick)
        try fm.removeItem(at: store.absoluteURL(for: game))

        XCTAssertNoThrow(try store.remove(game))

        XCTAssertTrue(store.games.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: sram.path))
        XCTAssertFalse(fm.fileExists(atPath: quick.path))
    }

    func testScanFlagsRowWhoseROMIsGoneWithoutDeletingSaves() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let game = try XCTUnwrap(store.importFiles(from: [inboxFile("Gone.gba")]).first)
        let sram = SavePaths(fileManager: fm, documentsURL: root).sramURL(forRelativeROMPath: game.relativePath)
        try Data([0xAA]).write(to: sram)
        try fm.removeItem(at: store.absoluteURL(for: game))

        await store.reconcileWithGamesFolder()

        XCTAssertEqual(store.missingGameIDs, [game.id])
        XCTAssertEqual(store.games.map(\.id), [game.id])
        XCTAssertTrue(fm.fileExists(atPath: sram.path))
    }

    func testScanAddsROMDroppedIntoGamesFolder() async throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        _ = try store.importFiles(from: [inboxFile("Game.gba")])
        try Data("nds".utf8).write(to: store.gamesDirectoryURL.appendingPathComponent("Game.nds"))
        try Data("txt".utf8).write(to: store.gamesDirectoryURL.appendingPathComponent("notes.txt"))

        await store.reconcileWithGamesFolder()

        XCTAssertEqual(store.games.count, 2)
        let nds = try XCTUnwrap(store.games.first { $0.systemID == .nds })
        // Renamed so it does not share Game.gba's saves.
        XCTAssertEqual(nds.relativePath, "Game-1.nds")
        XCTAssertTrue(fm.fileExists(atPath: store.absoluteURL(for: nds).path))

        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertEqual(reloaded.games.count, 2)
    }

    // MARK: - PSP SAVEDATA ownership (4)

    func testPSPCleanupRemovesSuffixedSaveFoldersOnly() throws {
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let mine = ["ULUS10041", "ULUS10041DATA00", "ULUS10041SYSDATA"]
        let others = ["ULUS10042DATA00", "ULES10041DATA00"]
        for name in mine + others {
            try fm.createDirectory(
                at: paths.pspSavedataDirectory.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let game = LibraryGame(displayName: "G", systemID: .psp, relativePath: "G.iso", pspProductID: "ULUS10041")
        try Data("iso".utf8).write(to: paths.gameROMURL(forRelativePath: game.relativePath))

        let result = try GameArtifactCleanup.removeArtifacts(for: game, paths: paths, fileManager: fm)

        XCTAssertEqual(result, .complete)
        for name in mine {
            XCTAssertFalse(fm.fileExists(atPath: paths.pspSavedataDirectory.appendingPathComponent(name).path), name)
        }
        for name in others {
            XCTAssertTrue(fm.fileExists(atPath: paths.pspSavedataDirectory.appendingPathComponent(name).path), name)
        }
    }

    func testPSPCleanupKeepsSavedataWhenAnotherRowSharesProductID() throws {
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let folder = paths.pspSavedataDirectory.appendingPathComponent("ULUS10041DATA00", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let iso = LibraryGame(displayName: "G", systemID: .psp, relativePath: "G.iso", pspProductID: "ULUS10041")
        let pbp = LibraryGame(displayName: "G2", systemID: .psp, relativePath: "G2.pbp", pspProductID: "ULUS10041")
        try Data("iso".utf8).write(to: paths.gameROMURL(forRelativePath: iso.relativePath))

        let result = try GameArtifactCleanup.removeArtifacts(for: iso, paths: paths, otherGames: [pbp], fileManager: fm)

        XCTAssertTrue(result.retainedPSPSavedata)
        XCTAssertTrue(fm.fileExists(atPath: folder.path))
    }

    func testPSPSaveFolderOwnership() {
        XCTAssertTrue(SaveGameImporter.isValidPSPSaveFolderName("ULUS10041DATA00"))
        XCTAssertTrue(SaveGameImporter.isValidPSPSaveFolderName("UCUS98648PROFILE00"))
        XCTAssertTrue(SaveGameImporter.isValidPSPSaveFolderName("ULUS10041"))
        XCTAssertFalse(SaveGameImporter.isValidPSPSaveFolderName("SAVEDATA"))
        XCTAssertFalse(SaveGameImporter.isValidPSPSaveFolderName("ULUS10041DATA00-EXTRA"))
        XCTAssertTrue(SaveGameImporter.pspSaveFolder("ULUS10041DATA00", belongsTo: "ULUS10041"))
        XCTAssertFalse(SaveGameImporter.pspSaveFolder("ULUS10042DATA00", belongsTo: "ULUS10041"))
    }

    func testPSPImportAcceptsSuffixedSaveFolderForMatchingGame() throws {
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let folder = root.appendingPathComponent("ULUS10041DATA00", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("SFO".utf8).write(to: folder.appendingPathComponent("PARAM.SFO"))
        let game = LibraryGame(displayName: "G", systemID: .psp, relativePath: "G.iso", pspProductID: "ULUS10041")

        let plan = try SaveGameImporter().planImport(from: folder, for: game, paths: paths, fileManager: fm)
        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/SAVEDATA/ULUS10041DATA00"))

        let other = LibraryGame(displayName: "O", systemID: .psp, relativePath: "O.iso", pspProductID: "ULUS10042")
        XCTAssertThrowsError(try SaveGameImporter().planImport(from: folder, for: other, paths: paths, fileManager: fm)) { error in
            XCTAssertEqual(error as? SaveGameImportError, .pspTitleMismatch(expected: "ULUS10042", imported: "ULUS10041DATA00"))
        }
    }

    // MARK: - Malformed ISO directory sizes (5)

    func testISOWithOversizedDirectoryIsRejected() throws {
        let sfo = Self.paramSFO(discID: "ULUS-10041")
        let good = root.appendingPathComponent("good.iso")
        try Self.makeISO(pspGameDirectorySize: 2048, sfo: sfo).write(to: good)
        let bad = root.appendingPathComponent("bad.iso")
        try Self.makeISO(pspGameDirectorySize: 0xFFFF_0000, sfo: sfo).write(to: bad)

        XCTAssertEqual(PSPProductIDExtractor.extract(from: good), .found("ULUS10041"))
        XCTAssertEqual(PSPProductIDExtractor.extract(from: bad), .notFound)
        XCTAssertNil(CoverArtExtractor.extractImageData(from: bad, system: .psp))
    }

    // MARK: - App data leaves Documents (9)

    func testLegacyLibraryCoversAndCacheMoveOutOfDocuments() throws {
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        try fm.createDirectory(at: documents.appendingPathComponent("Games"), withIntermediateDirectories: true)
        try Data("rom".utf8).write(to: documents.appendingPathComponent("Games/Zelda.gba"))
        let game = LibraryGame(displayName: "Zelda", systemID: .gba, relativePath: "Zelda.gba")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([game]).write(to: documents.appendingPathComponent("library.json"))
        try fm.createDirectory(at: documents.appendingPathComponent("Covers"), withIntermediateDirectories: true)
        try Data([0xDD]).write(to: documents.appendingPathComponent("Covers/\(game.id.uuidString).jpg"))
        try fm.createDirectory(at: documents.appendingPathComponent("Cache/psp"), withIntermediateDirectories: true)
        try Data([0xEE]).write(to: documents.appendingPathComponent("Cache/psp/shader.bin"))

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)

        XCTAssertEqual(store.games.map(\.id), [game.id])
        XCTAssertNil(store.libraryLoadFailureMessage)
        XCTAssertEqual(store.libraryFileURL.deletingLastPathComponent().standardizedFileURL, support.standardizedFileURL)
        XCTAssertFalse(fm.fileExists(atPath: documents.appendingPathComponent("library.json").path))
        XCTAssertFalse(fm.fileExists(atPath: documents.appendingPathComponent("Covers").path))
        XCTAssertFalse(fm.fileExists(atPath: documents.appendingPathComponent("Cache").path))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("Covers/\(game.id.uuidString).jpg").path))
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("Cache/psp/shader.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("Games/Zelda.gba").path))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("Saves").path))

        let covers = CoverArtStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)
        XCTAssertTrue(covers.hasCover(forGameID: game.id))
    }

    func testMigrationDoesNotOverwriteExistingSupportLibrary() throws {
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: documents.appendingPathComponent("library.json"))
        try Data("[]".utf8).write(to: support.appendingPathComponent("library.json"))

        let paths = SavePaths(fileManager: fm, documentsURL: documents, supportURL: support)
        try paths.migrateAppDataOutOfDocuments(fileManager: fm)

        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("library.json")), Data("[]".utf8))
        XCTAssertTrue(fm.fileExists(atPath: documents.appendingPathComponent("library.json").path))
    }

    // MARK: - Duplicates and corrupt library (10)

    func testReimportingSameFileIsSkippedAsDuplicate() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        let source = try inboxFile("Zelda.gba", "same-bytes")
        XCTAssertEqual(try store.importFiles(from: [source]).count, 1)

        let again = try store.importSummary(from: [source])
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.duplicates, ["Zelda.gba"])

        // Same bytes under another name: caught by the head/tail fingerprint.
        let renamed = try store.importSummary(from: [inboxFile("Zelda (copy).gba", "same-bytes")])
        XCTAssertTrue(renamed.added.isEmpty)
        XCTAssertEqual(renamed.duplicates, ["Zelda (copy).gba"])

        XCTAssertEqual(store.games.count, 1)
        let files = try fm.contentsOfDirectory(atPath: store.gamesDirectoryURL.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(files, ["Zelda.gba"])
    }

    func testSameNameDifferentContentIsNotADuplicate() throws {
        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        _ = try store.importFiles(from: [inboxFile("Zelda.gba", "version-one")])
        let second = try store.importSummary(from: [inboxFile("Zelda.gba", "version-two!")])
        XCTAssertEqual(second.added.map(\.relativePath), ["Zelda-1.gba"])
        XCTAssertTrue(second.duplicates.isEmpty)
    }

    func testCorruptLibraryIsBackedUpBeforeNextSave() throws {
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try fm.createDirectory(at: paths.supportURL, withIntermediateDirectories: true)
        let corrupt = Data("{ not valid json".utf8)
        try corrupt.write(to: paths.libraryFileURL)

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertNotNil(store.libraryLoadFailureMessage)
        let backup = try XCTUnwrap(store.corruptLibraryBackupURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("library.json.corrupt-"))

        _ = try store.importFiles(from: [inboxFile("Zelda.gba")])

        XCTAssertEqual(try Data(contentsOf: backup), corrupt)
        XCTAssertNotEqual(try Data(contentsOf: paths.libraryFileURL), corrupt)
    }

    // MARK: - Fixtures

    /// PVD → root (sector 20) → PSP_GAME (sector 21, size under test) → PARAM.SFO (sector 22).
    private static func makeISO(pspGameDirectorySize: UInt32, sfo: Data) -> Data {
        let sector = 2048
        var iso = Data(repeating: 0, count: sector * 24)
        let pvd = 16 * sector
        iso[pvd] = 1
        iso.replaceSubrange((pvd + 1)..<(pvd + 6), with: Data("CD001".utf8))
        iso.replaceSubrange((pvd + 156 + 2)..<(pvd + 156 + 6), with: u32LE(20))
        iso.replaceSubrange((pvd + 156 + 10)..<(pvd + 156 + 14), with: u32LE(UInt32(sector)))

        let pspGame = directoryRecord(name: "PSP_GAME", lba: 21, size: pspGameDirectorySize, isDir: true)
        iso.replaceSubrange((20 * sector)..<(20 * sector + pspGame.count), with: pspGame)
        let param = directoryRecord(name: "PARAM.SFO;1", lba: 22, size: UInt32(sfo.count), isDir: false)
        iso.replaceSubrange((21 * sector)..<(21 * sector + param.count), with: param)
        iso.replaceSubrange((22 * sector)..<(22 * sector + sfo.count), with: sfo)
        return iso
    }

    private static func directoryRecord(name: String, lba: UInt32, size: UInt32, isDir: Bool) -> Data {
        let nameBytes = Data(name.utf8)
        var rec = Data(repeating: 0, count: 33)
        rec.replaceSubrange(2..<6, with: u32LE(lba))
        rec.replaceSubrange(10..<14, with: u32LE(size))
        rec[25] = isDir ? 0x02 : 0x00
        rec[32] = UInt8(nameBytes.count)
        rec.append(nameBytes)
        if rec.count % 2 == 1 { rec.append(0) }
        rec[0] = UInt8(rec.count)
        return rec
    }

    private static func paramSFO(discID: String) -> Data {
        let key = Data("DISC_ID\0".utf8)
        let value = Data((discID + "\0").utf8)
        let keyTableOffset = 20 + 16
        let dataTableOffset = keyTableOffset + key.count
        var data = Data()
        data.append(u32LE(0x46535000))
        data.append(u32LE(0x00000101))
        data.append(u32LE(UInt32(keyTableOffset)))
        data.append(u32LE(UInt32(dataTableOffset)))
        data.append(u32LE(1))
        data.append(Data([0, 0, 4, 0]))
        data.append(u32LE(UInt32(value.count)))
        data.append(u32LE(UInt32(value.count)))
        data.append(u32LE(0))
        data.append(key)
        data.append(value)
        return data
    }

    private static func u32LE(_ value: UInt32) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: 4)
    }
}

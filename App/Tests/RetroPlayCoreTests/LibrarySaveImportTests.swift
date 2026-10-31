// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Library "+" → Saves: scanning picked files and folders, matching saves to games, and
/// writing them. Every test builds its own fixture tree in a fresh temporary folder.
final class LibrarySaveImportTests: XCTestCase {
    private var root: URL!
    private var pick: URL!
    private var paths: SavePaths!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-library-saves-\(UUID().uuidString)", isDirectory: true)
        pick = root.appendingPathComponent("Pick", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        paths = SavePaths(fileManager: fm, documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories(fileManager: fm)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    // MARK: Fixtures

    private func game(_ file: String, _ system: SystemID, pspID: String? = nil) -> LibraryGame {
        LibraryGame(
            displayName: (file as NSString).deletingPathExtension,
            systemID: system,
            relativePath: file,
            pspProductID: pspID
        )
    }

    @discardableResult
    private func file(_ relative: String, size: Int, fill: UInt8 = 0xAB, modified: Date? = nil) throws -> URL {
        let url = pick.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: size).write(to: url)
        if let modified {
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    private func pspSave(_ relative: String, param: Bool = true) throws -> URL {
        let url = pick.appendingPathComponent(relative, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        if param { try Data("PSF".utf8).write(to: url.appendingPathComponent("PARAM.SFO")) }
        try Data("DATA".utf8).write(to: url.appendingPathComponent("DATA.BIN"))
        return url
    }

    private func plan(_ urls: [URL]? = nil, games: [LibraryGame], limits: SaveScanLimits = SaveScanLimits()) -> SaveImportBatch {
        let scan = SaveFolderScanner.scan(urls ?? [pick], limits: limits, fileManager: fm)
        return LibrarySaveImporter().plan(scan, games: games, paths: paths, fileManager: fm)
    }

    private func item(for game: LibraryGame, in batch: SaveImportBatch) -> SaveImportItem? {
        batch.items.first { $0.game.id == game.id }
    }

    private func skipReason(_ suffix: String, in batch: SaveImportBatch) -> String? {
        batch.skipped.first { $0.name.hasSuffix(suffix) }?.reason
    }

    // MARK: RetroArch tree

    func testRetroArchSavesTreeMatchesEachCoreFolder() throws {
        let zelda = game("Zelda (USA).gba", .gba)
        let mario = game("Super Mario World (USA).sfc", .snes)
        let mario64 = game("Super Mario 64 (USA).z64", .n64)
        let ff7 = game("Final Fantasy VII (USA).cue", .ps1)
        try file("saves/mGBA/Zelda (USA).srm", size: 32_768)
        try file("saves/Snes9x/Super Mario World (USA).srm", size: 2_048)
        try file("saves/Mupen64Plus-Next/Super Mario 64 (USA).srm", size: SaveFormat.n64CombinedSRMSize)
        try file("saves/PCSX-ReARMed/Final Fantasy VII (USA).srm", size: 131_072)
        try file("states/mGBA/Zelda (USA).state", size: 100)
        try file("states/mGBA/Zelda (USA).state1", size: 100)
        try file("saves/readme.txt", size: 10)

        let batch = plan(games: [zelda, mario, mario64, ff7])

        XCTAssertEqual(batch.items.count, 4, "\(batch.skipped)")
        XCTAssertEqual(item(for: zelda, in: batch)?.plan.destinationURL, paths.sramURL(forRelativeROMPath: zelda.relativePath))
        XCTAssertEqual(item(for: mario, in: batch)?.plan.destinationURL, paths.sramURL(forRelativeROMPath: mario.relativePath))
        XCTAssertEqual(item(for: mario64, in: batch)?.plan.destinationURL, paths.n64SRAMURL(forRelativeROMPath: mario64.relativePath))
        XCTAssertEqual(item(for: ff7, in: batch)?.plan.destinationURL, paths.sramURL(forRelativeROMPath: ff7.relativePath))
        XCTAssertEqual(batch.gameCount, 4)
        XCTAssertNotNil(skipReason("Zelda (USA).state", in: batch))
        XCTAssertNotNil(skipReason("Zelda (USA).state1", in: batch))
        XCTAssertEqual(batch.ignoredFiles, 1)
    }

    // MARK: Names

    func testMatchesAcrossCaseRegionTagsAndArticles() throws {
        let emerald = game("Pokemon Emerald (USA, Europe).gba", .gba)
        let zelda = game("Legend of Zelda, The - A Link to the Past (USA).sfc", .snes)
        let kirby = game("Kirby.nds", .nds)
        try file("pokemon emerald (Rev 1).SAV", size: 131_072)
        try file("The Legend of Zelda - A Link to the Past.srm", size: 8_192)
        try file("KIRBY.sav", size: 524_288)

        let batch = plan(games: [emerald, zelda, kirby])

        XCTAssertNotNil(item(for: emerald, in: batch), "\(batch.skipped)")
        XCTAssertNotNil(item(for: zelda, in: batch), "\(batch.skipped)")
        XCTAssertNotNil(item(for: kirby, in: batch), "\(batch.skipped)")
    }

    func testExactNameWinsOverRegionlessTitleAndAmbiguityIsReported() throws {
        let usa = game("Zelda (USA).gba", .gba)
        let europe = game("Zelda (Europe).gba", .gba)
        try file("A/Zelda (Europe).sav", size: 8_192)
        try file("B/Zelda.sav", size: 8_192)

        let batch = plan(games: [usa, europe])

        XCTAssertEqual(batch.items.map(\.game.id), [europe.id])
        let reason = try XCTUnwrap(skipReason("B/Zelda.sav", in: batch))
        XCTAssertTrue(reason.contains("more than one game"), reason)
    }

    func testSimilarTitlesDoNotMatchEachOther() throws {
        let kart = game("Mario Kart.sfc", .snes)
        let kart64 = game("Mario Kart 64.z64", .n64)
        try file("Mario Kart 64.srm", size: SaveFormat.n64CombinedSRMSize)

        let batch = plan(games: [kart, kart64])

        XCTAssertEqual(batch.items.map(\.game.id), [kart64.id])
    }

    func testUnmatchedSaveIsReportedNotGuessed() throws {
        try file("Metroid Fusion.sav", size: 8_192)
        let batch = plan(games: [game("Metroid Zero Mission.gba", .gba)])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(skipReason("Metroid Fusion.sav", in: batch)).contains("No game"))
    }

    // MARK: Systems

    func testSizeAndExtensionPickTheSystem() throws {
        let gbaTetris = game("Tetris.gba", .gba)
        let n64Tetris = game("Tetris.z64", .n64)
        try file("Tetris.srm", size: SaveFormat.n64CombinedSRMSize)

        let batch = plan(games: [gbaTetris, n64Tetris])

        XCTAssertEqual(batch.items.map(\.game.id), [n64Tetris.id])
    }

    func testFolderHintSettlesASaveTwoSystemsCouldRead() throws {
        let nes = game("Tetris.nes", .nes)
        let gba = game("Tetris.gba", .gba)
        try file("saves/Nestopia/Tetris.srm", size: 8_192)
        try file("loose/Tetris.srm", size: 8_192)

        let batch = plan(games: [nes, gba])

        XCTAssertEqual(batch.items.map(\.game.id), [nes.id])
        XCTAssertTrue(try XCTUnwrap(skipReason("loose/Tetris.srm", in: batch)).contains("more than one game"))
    }

    func testRomExtensionInSaveNamePicksTheSystem() throws {
        let nes = game("Tetris.nes", .nes)
        let gba = game("Tetris.gba", .gba)
        try file("Tetris.gba.sav", size: 8_192)

        let batch = plan(games: [nes, gba])

        XCTAssertEqual(batch.items.map(\.game.id), [gba.id])
    }

    func testWrongSizeIsSkippedWithTheSystemsRule() throws {
        try file("Zelda.sav", size: 1_000)
        try file("Mario.srm", size: 512)
        let batch = plan(games: [game("Zelda.gba", .gba), game("Mario.z64", .n64)])

        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertEqual(skipReason("Zelda.sav", in: batch), SaveGameImportError.invalidSize(system: .gba, bytes: 1_000).localizedDescription)
        XCTAssertEqual(skipReason("Mario.srm", in: batch), SaveGameImportError.invalidSize(system: .n64, bytes: 512).localizedDescription)
    }

    func testRzipCompressedSaveIsSkipped() throws {
        let url = try file("Zelda.srm", size: 32_768)
        var data = Data("#RZIPv\u{1}#".utf8)
        data.append(Data(count: 32_768 - data.count))
        try data.write(to: url)

        let batch = plan(games: [game("Zelda.gba", .gba)])

        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertEqual(skipReason("Zelda.srm", in: batch), SaveGameImportError.compressedRetroArchSave.localizedDescription)
    }

    func testLooseN64FilesExplainThePacking() throws {
        try file("Mario.eep", size: 512)
        let batch = plan(games: [game("Mario.z64", .n64)])
        XCTAssertTrue(try XCTUnwrap(skipReason("Mario.eep", in: batch)).contains("290 KiB"))
    }

    func testPS1MemoryCardsIncludingDuckStationSlotNames() throws {
        let crash = game("Crash Bandicoot (USA).cue", .ps1)
        let spyro = game("Spyro the Dragon (USA).cue", .ps1)
        try file("memcards/Crash Bandicoot (USA)_1.mcd", size: 131_072)
        try file("memcards/Spyro the Dragon (USA).mcr", size: 8_192)

        let batch = plan(games: [crash, spyro])

        XCTAssertEqual(batch.items.map(\.game.id), [crash.id])
        XCTAssertEqual(
            skipReason("Spyro the Dragon (USA).mcr", in: batch),
            SaveGameImportError.invalidSize(system: .ps1, bytes: 8_192).localizedDescription
        )
    }

    // MARK: PSP

    func testPSPSavedataFoldersMatchByProductID() throws {
        let gow = game("God of War.iso", .psp, pspID: "UCUS98737")
        try pspSave("PSP/SAVEDATA/UCUS98737DATA00")
        try pspSave("PSP/SAVEDATA/UCUS98737SYSTEM")
        try pspSave("PSP/SAVEDATA/ULUS10041DATA00")
        try pspSave("PSP/SAVEDATA/UCUS98737DATA01", param: false)

        let batch = plan(games: [gow])

        XCTAssertEqual(
            Set(batch.items.map(\.plan.destinationURL.lastPathComponent)),
            ["UCUS98737DATA00", "UCUS98737SYSTEM"]
        )
        XCTAssertTrue(batch.items.allSatisfy { $0.game.id == gow.id })
        XCTAssertTrue(try XCTUnwrap(skipReason("ULUS10041DATA00", in: batch)).contains("ULUS10041"))
        XCTAssertEqual(skipReason("UCUS98737DATA01", in: batch), SaveGameImportError.missingPSPMetadata.localizedDescription)
        // The slot's own files aren't looked at as loose saves.
        XCTAssertFalse(batch.skipped.contains { $0.name.hasSuffix("DATA.BIN") })
    }

    func testPickedSlotFolderAndFileDirectly() throws {
        let gow = game("God of War.iso", .psp, pspID: "UCUS98737")
        let zelda = game("Zelda.gba", .gba)
        let slot = try pspSave("UCUS98737DATA00")
        let save = try file("Zelda.sav", size: 8_192)

        let batch = plan([slot, save], games: [gow, zelda])

        XCTAssertEqual(Set(batch.items.map(\.game.id)), [gow.id, zelda.id])
    }

    // MARK: Duplicates and existing saves

    func testNewestCopyOfTheSameSaveWins() throws {
        let zelda = game("Zelda.gba", .gba)
        let now = Date()
        try file("old/Zelda.sav", size: 8_192, fill: 1, modified: now.addingTimeInterval(-3_600))
        try file("new/Zelda.srm", size: 8_192, fill: 2, modified: now)

        let batch = plan(games: [zelda])

        XCTAssertEqual(batch.items.count, 1)
        XCTAssertEqual(batch.items.first?.sourceName, "Pick/new/Zelda.srm")
        XCTAssertTrue(try XCTUnwrap(skipReason("old/Zelda.sav", in: batch)).contains("newer"))
    }

    func testIdenticalExistingSaveIsAlreadyUpToDate() throws {
        let zelda = game("Zelda.gba", .gba)
        let mario = game("Mario.gba", .gba)
        try file("Zelda.sav", size: 8_192, fill: 7)
        try file("Mario.sav", size: 8_192, fill: 7)
        try Data(repeating: 7, count: 8_192).write(to: paths.sramURL(forRelativeROMPath: zelda.relativePath))
        try Data(repeating: 9, count: 8_192).write(to: paths.sramURL(forRelativeROMPath: mario.relativePath))

        let batch = plan(games: [zelda, mario])

        XCTAssertEqual(batch.items.map(\.game.id), [mario.id])
        XCTAssertTrue(batch.items[0].replacesExisting)
        XCTAssertEqual(batch.replacements.count, 1)
        XCTAssertTrue(try XCTUnwrap(skipReason("Zelda.sav", in: batch)).contains("already has"))
    }

    // MARK: Junk and limits

    func testArchivesHiddenFilesAndICloudPlaceholders() throws {
        try file("saves.zip", size: 100)
        try file(".hidden/Zelda.sav", size: 8_192)
        try file("cloud/.Zelda.sav.icloud", size: 100)
        try file("cloud/.DS_Store", size: 10)

        let batch = plan(games: [game("Zelda.gba", .gba)])

        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(skipReason("saves.zip", in: batch)).contains("unzip"))
        XCTAssertTrue(try XCTUnwrap(skipReason("cloud/Zelda.sav", in: batch)).contains("iCloud"))
        XCTAssertFalse(batch.skipped.contains { $0.name.contains(".hidden") })
    }

    func testDeepNestingIsFoundWithinTheDepthLimit() throws {
        let zelda = game("Zelda.gba", .gba)
        try file("a/b/c/d/e/Zelda.sav", size: 8_192)

        XCTAssertNotNil(item(for: zelda, in: plan(games: [zelda])))
        let shallow = plan(games: [zelda], limits: SaveScanLimits(maxDepth: 3))
        XCTAssertTrue(shallow.items.isEmpty)
        XCTAssertTrue(shallow.truncated)
    }

    func testHugeFolderStopsAtTheEntryLimit() throws {
        for index in 0..<400 {
            try file("junk/\(index / 50)/file\(index).bin", size: 1)
        }
        try file("Zelda.sav", size: 8_192)

        let scan = SaveFolderScanner.scan([pick], limits: SaveScanLimits(maxEntries: 100), fileManager: fm)

        XCTAssertTrue(scan.truncated)
        XCTAssertLessThanOrEqual(scan.ignoredFiles, 100)
    }

    func testCandidateLimitStopsTheScan() throws {
        for index in 0..<20 {
            try file("Game\(index).sav", size: 8_192)
        }
        let scan = SaveFolderScanner.scan([pick], limits: SaveScanLimits(maxCandidates: 5), fileManager: fm)
        XCTAssertEqual(scan.candidates.count, 5)
        XCTAssertTrue(scan.truncated)
    }

    // MARK: Commit

    func testCommitKeepsOrReplacesExistingSaves() throws {
        let zelda = game("Zelda.gba", .gba)
        let mario = game("Mario.gba", .gba)
        let zeldaDest = paths.sramURL(forRelativeROMPath: zelda.relativePath)
        let marioDest = paths.sramURL(forRelativeROMPath: mario.relativePath)
        try Data(repeating: 1, count: 8_192).write(to: zeldaDest)
        try file("Zelda.sav", size: 8_192, fill: 2)
        try file("Mario.sav", size: 8_192, fill: 3)
        let batch = plan(games: [zelda, mario])
        let importer = LibrarySaveImporter()

        let keep = importer.commit(batch, replaceExisting: false, paths: paths, fileManager: fm)
        XCTAssertEqual(keep.imported.map(\.game.id), [mario.id])
        XCTAssertEqual(keep.kept.map(\.game.id), [zelda.id])
        XCTAssertEqual(try Data(contentsOf: zeldaDest), Data(repeating: 1, count: 8_192))
        XCTAssertEqual(try Data(contentsOf: marioDest), Data(repeating: 3, count: 8_192))

        let replace = importer.commit(batch, replaceExisting: true, paths: paths, fileManager: fm)
        XCTAssertEqual(Set(replace.imported.map(\.game.id)), [zelda.id, mario.id])
        XCTAssertEqual(try Data(contentsOf: zeldaDest), Data(repeating: 2, count: 8_192))
        XCTAssertTrue(replace.failed.isEmpty)
    }

    func testImportedGamesBootFreshUntilANewerQuickSave() throws {
        let zelda = game("Zelda.gba", .gba)
        let mario = game("Mario.gba", .gba)
        // A quick save from before the import: it holds the old save in memory.
        let quick = SaveStateStore.quickSaveDirectory(system: .gba, gameID: zelda.id, paths: paths)
        try fm.createDirectory(at: quick, withIntermediateDirectories: true)
        let old = try SaveStateStore.quickSaveURL(system: .gba, gameID: zelda.id, paths: paths)
        try Data([1]).write(to: old)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: old.path)
        try file("Zelda.sav", size: 8_192)

        _ = LibrarySaveImporter().commit(plan(games: [zelda, mario]), replaceExisting: false, paths: paths, fileManager: fm)

        // Still fresh on a second launch: the first fresh session may have died before saving.
        XCTAssertTrue(FreshBoot.isPending(zelda.id, system: .gba, paths: paths, fileManager: fm))
        XCTAssertTrue(FreshBoot.isPending(zelda.id, system: .gba, paths: paths, fileManager: fm))
        XCTAssertFalse(FreshBoot.isPending(mario.id, system: .gba, paths: paths, fileManager: fm))
        // Leaving the fresh session writes a newer quick save: resuming is safe again.
        try Data([2]).write(to: old)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: old.path)
        XCTAssertFalse(FreshBoot.isPending(zelda.id, system: .gba, paths: paths, fileManager: fm))
        // Kept: automatic resume still never falls back to a state from before the import.
        XCTAssertNotNil(FreshBoot.importDate(zelda.id, paths: paths))
    }

    func testEveryCopyOfAPSPGameBootsFresh() throws {
        let iso = game("God of War.iso", .psp, pspID: "UCUS98737")
        let cso = game("God of War.cso", .psp, pspID: "UCUS98737")
        try pspSave("SAVEDATA/UCUS98737DATA00")

        let outcome = LibrarySaveImporter().commit(plan(games: [iso, cso]), replaceExisting: false, paths: paths, fileManager: fm)

        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertTrue(FreshBoot.isPending(iso.id, system: .psp, paths: paths, fileManager: fm))
        XCTAssertTrue(FreshBoot.isPending(cso.id, system: .psp, paths: paths, fileManager: fm))
    }

    func testNoGameStartsWhileSavesAreBeingImported() {
        XCTAssertTrue(SaveImportPhase.idle.allowsLaunchingGames)
        for phase in [SaveImportPhase.scanning, .reviewing, .committing] {
            XCTAssertFalse(phase.allowsLaunchingGames, "\(phase)")
        }
        XCTAssertFalse(SaveImportPhase.mayWrite(gameOpen: true))
        XCTAssertTrue(SaveImportPhase.mayWrite(gameOpen: false))
    }

    func testCommitReplacesPSPSlotFolder() throws {
        let gow = game("God of War.iso", .psp, pspID: "UCUS98737")
        let existing = paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: existing.appendingPathComponent("OLD.BIN"))
        try pspSave("SAVEDATA/UCUS98737DATA00")

        let batch = plan(games: [gow])
        XCTAssertEqual(batch.replacements.count, 1)
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)

        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: existing.appendingPathComponent("PARAM.SFO").path))
        XCTAssertFalse(fm.fileExists(atPath: existing.appendingPathComponent("OLD.BIN").path))
    }

    // MARK: Pieces

    func testNormalizedTitle() {
        XCTAssertEqual(TitleIndex.normalizedTitle("Legend of Zelda, The - A Link to the Past (USA) [!]"), "the legend of zelda a link to the past")
        XCTAssertEqual(TitleIndex.normalizedTitle("Pokémon - Émeraude (France)"), "pokemon emeraude")
        XCTAssertEqual(TitleIndex.normalizedTitle("Banjo_&_Kazooie"), "banjo and kazooie")
        XCTAssertEqual(TitleIndex.normalizedTitle("(Demo)"), "")
    }

    func testSaveStateExtensions() {
        for ext in ["state", "state1", "state9", "auto", "ss0", "ppst"] {
            XCTAssertTrue(SaveImportContentTypes.isSaveStateExtension(ext), ext)
        }
        for ext in ["sav", "srm", "stats", "ssa"] {
            XCTAssertFalse(SaveImportContentTypes.isSaveStateExtension(ext), ext)
        }
    }

    func testSaveDestinations() {
        let saves = paths.savesDirectory.path
        let expected: [(SystemID, String, String)] = [
            (.gba, "Pocket/Zelda.gba", "\(saves)/Pocket/Zelda.sav"),
            (.nds, "Kirby.nds", "\(saves)/Kirby.sav"),
            (.n64, "Mario.z64", "\(saves)/n64/Mario.srm"),
            (.psp, "God of War.iso", "\(saves)/psp-memstick/PSP/SAVEDATA"),
            (.nes, "Zelda.nes", "\(saves)/Zelda.sav"),
            (.snes, "Chrono Trigger.sfc", "\(saves)/Chrono Trigger.sav"),
            (.genesis, "Sonic.md", "\(saves)/Sonic.sav"),
            (.atari7800, "Asteroids.a78", "\(saves)/Asteroids.sav"),
            (.ps1, "FF7/FF7.cue", "\(saves)/FF7/FF7.sav"),
        ]
        XCTAssertEqual(Set(expected.map(\.0)), Set(SystemID.allCases))
        for (system, rom, path) in expected {
            let game = LibraryGame(displayName: "x", systemID: system, relativePath: rom)
            XCTAssertEqual(SaveFormat.of(system).destination(for: game, paths: paths).path, path, "\(system)")
            XCTAssertEqual(paths.batterySaveURL(for: game).path, path, "\(system)")
        }
        XCTAssertTrue(SaveImportContentTypes.isBatteryExtension("mcd"))
        XCTAssertEqual(SaveFormat.n64CombinedSRMSize, 296_960)
    }

    func testInGameImportKeepsItsWiderRulesButTheScanDoesNot() throws {
        // Picked for this game in-game: taken, as before. Found in a folder: not a 128 KiB card.
        let card = try file("FF7.mcr", size: 8_192)
        let ff7 = game("FF7.cue", .ps1)
        XCTAssertNoThrow(try SaveGameImporter().planImport(from: card, for: ff7, paths: paths, fileManager: fm))
        XCTAssertTrue(plan(games: [ff7]).items.isEmpty)
    }
}

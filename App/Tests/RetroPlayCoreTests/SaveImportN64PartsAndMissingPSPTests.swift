// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Loose N64 saves (.eep, .mpk, .sra, .fla) merged into the game's combined save, region by
/// region, in the core's byte order; and PSP saves for games not in the library kept under
/// their own names.
final class SaveImportN64PartsAndMissingPSPTests: XCTestCase {
    private var root: URL!
    private var pick: URL!
    private var paths: SavePaths!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-n64-parts-\(UUID().uuidString)", isDirectory: true)
        pick = root.appendingPathComponent("Pick", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        paths = SavePaths(fileManager: fm, documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories(fileManager: fm)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private let mario = LibraryGame(displayName: "Super Mario 64", systemID: .n64, relativePath: "Super Mario 64 (USA).z64")
    private let kart = LibraryGame(displayName: "Mario Kart 64", systemID: .n64, relativePath: "Mario Kart 64 (USA).z64")

    @discardableResult
    private func write(_ relative: String, _ data: Data, modified: Date? = nil) throws -> URL {
        let url = pick.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    /// Bytes 0, 1, 2… (so a swap or an offset shows), `count` long.
    private func pattern(_ count: Int, seed: UInt8 = 0) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &+ Int(seed)) })
    }

    private func pak(_ fill: UInt8) -> Data {
        var pak = N64CombinedSave.formattedPak(serial: [1, 2, 3, 4, 5, 6])
        pak.replaceSubrange(0x300..<0x400, with: Data(repeating: fill, count: 0x100))
        return pak
    }

    private func plan(_ games: [LibraryGame]) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([pick], fileManager: fm), games: games, paths: paths, fileManager: fm)
    }

    private func region(_ data: Data, _ region: N64CombinedSave.Region) -> Data {
        data.subdata(in: region.offset..<region.offset + region.length)
    }

    // MARK: Layout and formatting

    func testTheLayoutIsTheCoresSaveMemory() {
        // libretro_memory.h: eeprom[0x800], mempack[4 × 0x8000], sram[0x8000], flashram[0x20000].
        XCTAssertEqual(N64CombinedSave.size, SaveFormat.n64CombinedSRMSize)
        XCTAssertEqual(N64CombinedSave.Region.eeprom.offset, 0)
        XCTAssertEqual(N64CombinedSave.Region.controllerPak(1).offset, 0x800)
        XCTAssertEqual(N64CombinedSave.Region.controllerPak(4).offset, 0x800 + 3 * 0x8000)
        XCTAssertEqual(N64CombinedSave.Region.sram.offset, 0x20800)
        XCTAssertEqual(N64CombinedSave.Region.flashRAM.offset, 0x28800)
    }

    func testABlankSaveIsAsTheCoreFormatsIt() {
        let blank = N64CombinedSave.blank()
        XCTAssertEqual(blank.count, N64CombinedSave.size)
        XCTAssertTrue(region(blank, .eeprom).allSatisfy { $0 == 0xFF })
        XCTAssertTrue(region(blank, .sram).allSatisfy { $0 == 0xFF })
        XCTAssertTrue(region(blank, .flashRAM).allSatisfy { $0 == 0xFF })
        for index in 1...4 {
            let pak = region(blank, .controllerPak(index))
            XCTAssertTrue(N64CombinedSave.isFormattedPak(pak), "pak \(index)")
            // Index table: pages 5… free (0x0003), and its backup on page 2.
            XCTAssertEqual(pak[0x100 + 10], 0x00); XCTAssertEqual(pak[0x100 + 11], 0x03)
            XCTAssertEqual(pak.subdata(in: 0x100..<0x200), pak.subdata(in: 0x200..<0x300))
            // ID block backups in blocks 3, 4 and 6.
            for block in [3, 4, 6] { XCTAssertEqual(pak.subdata(in: block * 32..<block * 32 + 32), pak.subdata(in: 32..<64)) }
        }
    }

    // MARK: Each loose type

    func testEEPROMOf4And16KbitIsCopiedAsIs() throws {
        for size in [512, 2048] {
            let parts = try N64CombinedSave.parts(extension: "eep", data: pattern(size), name: "Mario", folders: [])
            XCTAssertEqual(parts.map(\.region), [.eeprom])
            XCTAssertEqual(parts[0].bytes, pattern(size))
        }
        XCTAssertThrowsError(try N64CombinedSave.parts(extension: "eep", data: pattern(1000), name: "Mario", folders: []))
    }

    func testAControllerPakIsKeptInItsOrderAndAWordSwappedOneIsTurnedBack() throws {
        let original = pak(0x42)
        let asIs = try N64CombinedSave.parts(extension: "mpk", data: original, name: "Mario Kart 64", folders: [])
        XCTAssertEqual(asIs.map(\.region), [.controllerPak(1)])
        XCTAssertEqual(asIs[0].bytes, original)
        let swapped = try N64CombinedSave.parts(extension: "mpk", data: N64CombinedSave.swappingWords(original), name: "Mario Kart 64_2", folders: [])
        XCTAssertEqual(swapped.map(\.region), [.controllerPak(2)])
        XCTAssertEqual(swapped[0].bytes, original)
    }

    func testAFourPakFileFillsEachFormattedPak() throws {
        var four = Data()
        for fill in [UInt8(1), 2, 3] { four += pak(fill) }
        four += Data(count: N64CombinedSave.pakSize)   // pak 4 never formatted
        let parts = try N64CombinedSave.parts(extension: "mpk", data: four, name: "Mario Kart 64", folders: [])
        XCTAssertEqual(parts.map(\.region), [.controllerPak(1), .controllerPak(2), .controllerPak(3)])
        XCTAssertEqual(parts[1].bytes, pak(2))
    }

    func testAnUnformattedPakIsRefused() {
        XCTAssertThrowsError(try N64CombinedSave.parts(extension: "mpk", data: Data(count: 0x8000), name: "Mario", folders: [])) {
            XCTAssertEqual($0 as? N64CombinedSave.ImportError, .notAControllerPak)
        }
    }

    func testSRAMAndFlashRAMFromAnEmulatorAreCopiedAndFromAFlashCartSwapped() throws {
        let sram = pattern(0x8000)
        let emulator = try N64CombinedSave.parts(extension: "sra", data: sram, name: "Zelda", folders: ["Project64", "Save"])
        XCTAssertEqual(emulator[0].bytes, sram)
        XCTAssertNotNil(emulator[0].note, "an assumed byte order is said")
        let cart = try N64CombinedSave.parts(extension: "sra", data: sram, name: "Zelda", folders: ["ED64", "gamedata"])
        XCTAssertEqual(cart[0].bytes, N64CombinedSave.swappingWords(sram))
        XCTAssertNil(cart[0].note)
        XCTAssertEqual(cart[0].bytes.prefix(4), Data([3, 2, 1, 0]))
        let flash = try N64CombinedSave.parts(extension: "fla", data: pattern(0x20000), name: "Zelda", folders: [])
        XCTAssertEqual(flash.map(\.region), [.flashRAM])
        XCTAssertThrowsError(try N64CombinedSave.parts(extension: "fla", data: pattern(0x8000), name: "Zelda", folders: []))
    }

    func testMergingWritesOnlyTheGivenRegions() {
        var existing = N64CombinedSave.blank()
        existing.replaceSubrange(N64CombinedSave.sramOffset..<N64CombinedSave.sramOffset + 4, with: Data([9, 9, 9, 9]))
        let existingPak2 = region(existing, .controllerPak(2))
        let merged = N64CombinedSave.merge([
            .init(region: .eeprom, bytes: pattern(512)),
            .init(region: .controllerPak(1), bytes: pak(7)),
        ], into: existing)
        XCTAssertEqual(merged.count, N64CombinedSave.size)
        XCTAssertEqual(merged.prefix(512), pattern(512))
        XCTAssertTrue(merged.subdata(in: 512..<0x800).allSatisfy { $0 == 0xFF }, "a 4 Kbit EEPROM leaves the rest of its region")
        XCTAssertEqual(region(merged, .controllerPak(1)), pak(7))
        XCTAssertEqual(region(merged, .controllerPak(2)), existingPak2)
        XCTAssertEqual(merged.subdata(in: N64CombinedSave.sramOffset..<N64CombinedSave.sramOffset + 4), Data([9, 9, 9, 9]))
    }

    // MARK: Planning and importing

    func testLooseFilesForOneGameAreOneItemSayingWhatTheyAdd() throws {
        try write("saves/Super Mario 64 (USA).eep", pattern(512))
        try write("saves/Mario Kart 64 (USA).mpk", pak(1))
        try write("saves/Mario Kart 64 (USA)_2.mpk", pak(2))
        let batch = plan([mario, kart])
        XCTAssertEqual(batch.items.count, 2, "\(batch.skipped)")
        let kartItem = try XCTUnwrap(batch.items.first { $0.game.id == kart.id })
        XCTAssertEqual(kartItem.addedParts, ["Controller Pak 1", "Controller Pak 2"])
        XCTAssertEqual(kartItem.plan.destinationURL, paths.n64SRAMURL(forRelativeROMPath: kart.relativePath))
        XCTAssertEqual(batch.items.first { $0.game.id == mario.id }?.addedParts, ["EEPROM"])
        XCTAssertFalse(kartItem.replacesExisting)
    }

    func testImportingMergesIntoTheExistingSaveAndKeepsTheRest() throws {
        let dest = paths.n64SRAMURL(forRelativeROMPath: mario.relativePath)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        var existing = N64CombinedSave.blank()
        existing.replaceSubrange(N64CombinedSave.flashOffset..<N64CombinedSave.flashOffset + 3, with: Data([5, 6, 7]))
        try existing.write(to: dest)
        try write("Super Mario 64 (USA).eep", pattern(2048, seed: 3))

        let batch = plan([mario])
        let item = try XCTUnwrap(batch.items.first)
        XCTAssertTrue(item.replacesExisting)
        // Keep: the save here stays as it is.
        let kept = LibrarySaveImporter().commit(batch, replaceExisting: false, paths: paths, fileManager: fm)
        XCTAssertEqual(kept.kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: dest), existing)
        // Replace: only the EEPROM changes.
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)
        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        let after = try Data(contentsOf: dest)
        XCTAssertEqual(region(after, .eeprom), pattern(2048, seed: 3))
        XCTAssertEqual(region(after, .flashRAM), region(existing, .flashRAM))
        XCTAssertEqual(region(after, .controllerPak(3)), region(existing, .controllerPak(3)))
    }

    func testImportingWithNoSaveStartsFromABlankOne() throws {
        try write("Super Mario 64 (USA).sra", pattern(0x8000))
        let outcome = LibrarySaveImporter().commit(plan([mario]), replaceExisting: true, paths: paths, fileManager: fm)
        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        let saved = try Data(contentsOf: paths.n64SRAMURL(forRelativeROMPath: mario.relativePath))
        XCTAssertEqual(saved.count, N64CombinedSave.size)
        XCTAssertEqual(region(saved, .sram), pattern(0x8000))
        XCTAssertTrue(region(saved, .eeprom).allSatisfy { $0 == 0xFF })
        XCTAssertTrue(N64CombinedSave.isFormattedPak(region(saved, .controllerPak(1))))
    }

    func testTwoFilesForOneRegionUseTheNewer() throws {
        try write("a/Super Mario 64 (USA).eep", pattern(512, seed: 1), modified: Date(timeIntervalSince1970: 1_000))
        try write("b/Super Mario 64 (USA).eep", pattern(512, seed: 2), modified: Date(timeIntervalSince1970: 2_000))
        let batch = plan([mario])
        XCTAssertEqual(batch.items.first?.n64Parts.first?.bytes, pattern(512, seed: 2))
        XCTAssertTrue(batch.skipped.contains { $0.name.hasPrefix("Pick/a/") || $0.name.contains("a/Super") })
    }

    func testALooseFileForNoGameOrOfTheWrongSizeIsReported() throws {
        try write("Banjo-Kazooie.eep", pattern(512))
        try write("Super Mario 64 (USA).sra", pattern(100))
        let batch = plan([mario])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(batch.skipped.contains { $0.name.hasSuffix("Banjo-Kazooie.eep") && $0.reason.contains("No N64 game") }, "\(batch.skipped)")
        XCTAssertTrue(batch.skipped.contains { $0.name.hasSuffix(".sra") && $0.reason.contains("32 KiB") }, "\(batch.skipped)")
    }

    // MARK: PSP saves for games not in the library

    private func pspSave(_ name: String, data: String = "DATA") throws -> URL {
        let url = pick.appendingPathComponent("PSP/SAVEDATA/\(name)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("PSF".utf8).write(to: url.appendingPathComponent("PARAM.SFO"))
        try Data(data.utf8).write(to: url.appendingPathComponent("DATA.BIN"))
        return url
    }

    func testAPSPSaveForAGameNotInTheLibraryIsKeptUnderItsName() throws {
        try pspSave("ULUS10041SAVE00")
        let batch = plan([mario])
        let item = try XCTUnwrap(batch.forMissingGames.first, "\(batch.skipped)")
        XCTAssertEqual(item.game.displayName, "ULUS10041")
        XCTAssertTrue(item.gameIDs.isEmpty, "no game is marked to boot fresh")
        XCTAssertEqual(batch.gameCount, 0)
        XCTAssertTrue(batch.newSaves.isEmpty)
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)
        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        let installed = paths.pspSavedataDirectory.appendingPathComponent("ULUS10041SAVE00")
        XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent("DATA.BIN")), Data("DATA".utf8))
    }

    func testItReplacesAFolderHereOnlyWhenChosen() throws {
        let here = paths.pspSavedataDirectory.appendingPathComponent("ULUS10041SAVE00", isDirectory: true)
        try fm.createDirectory(at: here, withIntermediateDirectories: true)
        try Data("PSF".utf8).write(to: here.appendingPathComponent("PARAM.SFO"))
        try Data("OLD".utf8).write(to: here.appendingPathComponent("DATA.BIN"))
        try pspSave("ULUS10041SAVE00", data: "NEW")
        let batch = plan([])
        XCTAssertTrue(try XCTUnwrap(batch.forMissingGames.first).replacesExisting)
        _ = LibrarySaveImporter().commit(batch, replaceExisting: false, paths: paths, fileManager: fm)
        XCTAssertEqual(try Data(contentsOf: here.appendingPathComponent("DATA.BIN")), Data("OLD".utf8))
        _ = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)
        XCTAssertEqual(try Data(contentsOf: here.appendingPathComponent("DATA.BIN")), Data("NEW".utf8))
    }

    func testAnInvalidPSPFolderForAMissingGameIsStillRefused() throws {
        let url = pick.appendingPathComponent("PSP/SAVEDATA/ULUS10041SAVE00", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("DATA".utf8).write(to: url.appendingPathComponent("DATA.BIN"))   // no PARAM.SFO
        let batch = plan([])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertFalse(batch.skipped.isEmpty)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Save import cases found in review: conflicting hints, second memory cards, links, files that
/// change after the summary, folder limits, lower-case PSP folders, crash-safe PSP replace, and
/// every extension the in-game import took before. Each test builds its own temporary tree.
final class SaveImportHardeningTests: XCTestCase {
    private var root: URL!
    private var pick: URL!
    private var paths: SavePaths!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-hardening-\(UUID().uuidString)", isDirectory: true)
        pick = root.appendingPathComponent("Pick", isDirectory: true)
        try fm.createDirectory(at: pick, withIntermediateDirectories: true)
        paths = SavePaths(fileManager: fm, documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories(fileManager: fm)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func game(_ file: String, _ system: SystemID, pspID: String? = nil) -> LibraryGame {
        LibraryGame(displayName: (file as NSString).deletingPathExtension, systemID: system, relativePath: file, pspProductID: pspID)
    }

    @discardableResult
    private func file(_ relative: String, size: Int, fill: UInt8 = 0xAB, under base: URL? = nil) throws -> URL {
        let url = (base ?? pick).appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: size).write(to: url)
        return url
    }

    @discardableResult
    private func pspSave(_ relative: String, extraFiles: Int = 0) throws -> URL {
        let url = pick.appendingPathComponent(relative, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("PSF".utf8).write(to: url.appendingPathComponent("PARAM.SFO"))
        try Data("DATA".utf8).write(to: url.appendingPathComponent("DATA.BIN"))
        for index in 0..<extraFiles {
            try Data([1]).write(to: url.appendingPathComponent("F\(index).BIN"))
        }
        return url
    }

    private func plan(_ urls: [URL]? = nil, games: [LibraryGame], limits: SaveScanLimits = SaveScanLimits()) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan(urls ?? [pick], limits: limits, fileManager: fm), games: games, paths: paths, fileManager: fm)
    }

    private func reason(_ suffix: String, in batch: SaveImportBatch) -> String? {
        batch.skipped.first { $0.name.hasSuffix(suffix) }?.reason
    }

    // MARK: 1. Hints

    func testConflictingFolderHintIsRefusedEvenWithOneMatch() throws {
        try file("saves/melonDS/Chrono Trigger.sav", size: 524_288)
        let batch = plan(games: [game("Chrono Trigger.sfc", .snes)])
        XCTAssertTrue(batch.items.isEmpty, "\(batch.items.map(\.sourceName))")
        XCTAssertTrue(try XCTUnwrap(reason("Chrono Trigger.sav", in: batch)).contains("DS"))
    }

    func testConflictingRomExtensionInNameIsRefused() throws {
        try file("Chrono Trigger.gba.sav", size: 8_192)
        let batch = plan(games: [game("Chrono Trigger.sfc", .snes)])
        XCTAssertTrue(batch.items.isEmpty, "\(batch.items.map(\.sourceName))")
        XCTAssertNotNil(reason("Chrono Trigger.gba.sav", in: batch))
    }

    // MARK: 4. Second memory card

    func testDuckStationSecondCardIsRefused() throws {
        try file("memcards/Crash Bandicoot (USA)_2.mcd", size: 131_072)
        let batch = plan(games: [game("Crash Bandicoot (USA).cue", .ps1)])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reason("_2.mcd", in: batch)).contains("card 2"))
    }

    func testFirstCardSuffixDoesNotFallThroughToANumberedTitle() throws {
        let sequel = game("Crash 1.cue", .ps1)
        try file("Crash_1.mcd", size: 131_072)
        let batch = plan(games: [sequel])
        XCTAssertTrue(batch.items.isEmpty, "Crash_1.mcd is card 1 of “Crash”, not a save for “Crash 1”")
    }

    // MARK: 5. Links

    func testSymlinkedSaveIsNotImported() throws {
        let real = try file("Zelda.sav", size: 8_192, under: root.appendingPathComponent("Elsewhere"))
        try fm.createSymbolicLink(at: pick.appendingPathComponent("Zelda.sav"), withDestinationURL: real)
        // NES takes any size, so only the link itself can stop it.
        let batch = plan(games: [game("Zelda.nes", .nes)])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reason("Zelda.sav", in: batch)).contains("Links"))
    }

    func testPSPFolderWithALinkInsideIsNotImported() throws {
        let slot = try pspSave("SAVEDATA/UCUS98737DATA00")
        let real = try file("ICON0.PNG", size: 10, under: root.appendingPathComponent("Elsewhere"))
        try fm.createSymbolicLink(at: slot.appendingPathComponent("ICON0.PNG"), withDestinationURL: real)
        let batch = plan(games: [game("God of War.iso", .psp, pspID: "UCUS98737")])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reason("UCUS98737DATA00", in: batch)).contains("links"))
    }

    // MARK: 6. The bytes installed are checked

    func testSourceTruncatedAfterTheSummaryIsNotInstalled() throws {
        let zelda = game("Zelda.gba", .gba)
        let dest = paths.sramURL(forRelativeROMPath: zelda.relativePath)
        try Data(repeating: 1, count: 8_192).write(to: dest)
        let source = try file("Zelda.sav", size: 8_192, fill: 2)
        let batch = plan(games: [zelda])
        XCTAssertEqual(batch.items.count, 1)
        try Data().write(to: source)

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)

        XCTAssertTrue(outcome.imported.isEmpty)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: dest), Data(repeating: 1, count: 8_192))
        XCTAssertEqual(try leftovers(in: paths.savesDirectory), [])
    }

    func testPSPFolderEmptiedAfterTheSummaryLeavesTheOldSlot() throws {
        let gow = game("God of War.iso", .psp, pspID: "UCUS98737")
        let existing = paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: existing.appendingPathComponent("PARAM.SFO"))
        let slot = try pspSave("SAVEDATA/UCUS98737DATA00")
        let batch = plan(games: [gow])
        XCTAssertEqual(batch.items.count, 1)
        try fm.removeItem(at: slot.appendingPathComponent("PARAM.SFO"))

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: fm)

        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("PARAM.SFO")), Data("OLD".utf8))
        XCTAssertEqual(try leftovers(in: paths.pspSavedataDirectory), [])
    }

    // MARK: 7. Marker first

    func testMarkerFailureLeavesTheSaveUntouched() throws {
        let zelda = game("Zelda.gba", .gba)
        let dest = paths.sramURL(forRelativeROMPath: zelda.relativePath)
        try Data(repeating: 1, count: 8_192).write(to: dest)
        try file("Zelda.sav", size: 8_192, fill: 2)
        // The marker folder can't be made: a file is in its way.
        let markers = paths.freshBootMarkerURL(for: zelda.id).deletingLastPathComponent()
        try fm.createDirectory(at: markers.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: markers)

        let outcome = LibrarySaveImporter().commit(plan(games: [zelda]), replaceExisting: true, paths: paths, fileManager: fm)

        XCTAssertTrue(outcome.imported.isEmpty)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(try Data(contentsOf: dest), Data(repeating: 1, count: 8_192))
    }

    // MARK: 8. Nothing the in-game import took is refused

    func testInGameImportTakesEveryExtensionItTookBefore() throws {
        let legacy = ["sav", "srm", "eep", "fla", "sra", "mpk", "mcr"]
        for system in SystemID.allCases where system != .psp && system != .n64 {
            // A size every system's rules took before.
            let size = 8_192
            for ext in legacy {
                let source = try file("\(system.rawValue)/Game.\(ext)", size: size)
                let target = LibraryGame(displayName: "Game", systemID: system, relativePath: "Game.rom")
                XCTAssertNoThrow(
                    try SaveGameImporter().planImport(from: source, for: target, paths: paths, fileManager: fm),
                    "\(system) .\(ext)"
                )
            }
        }
        let n64 = try file("n64/Game.srm", size: 296_960)
        XCTAssertNoThrow(try SaveGameImporter().planImport(from: n64, for: game("Game.z64", .n64), paths: paths, fileManager: fm))
    }

    func testLibraryScanTakesRetroPlayAndRetroArchExtensions() throws {
        let ff7 = game("FF7.cue", .ps1)
        let kirby = game("Kirby.nds", .nds)
        try file("FF7.sav", size: 131_072)
        try file("Kirby.srm", size: 524_288)
        let batch = plan(games: [ff7, kirby])
        XCTAssertEqual(Set(batch.items.map(\.game.id)), [ff7.id, kirby.id], "\(batch.skipped)")
    }

    // MARK: 9. Limits

    func testPickedPSPFoldersCountTowardTheLimits() throws {
        let slots = try (0..<10).map { try pspSave(String(format: "UCUS98737DATA%02d", $0)) }
        let scan = SaveFolderScanner.scan(slots, limits: SaveScanLimits(maxCandidates: 3), fileManager: fm)
        XCTAssertEqual(scan.candidates.count, 3)
        XCTAssertTrue(scan.truncated)
    }

    func testOversizedPSPFolderIsRefused() throws {
        try pspSave("SAVEDATA/UCUS98737DATA00", extraFiles: 300)
        let batch = plan(games: [game("God of War.iso", .psp, pspID: "UCUS98737")])
        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertTrue(try XCTUnwrap(reason("UCUS98737DATA00", in: batch)).contains("Too big"))
    }

    // MARK: 10. Case

    func testLowerCasePSPFolderIsFound() throws {
        try pspSave("savedata/ucus98737data00")
        let batch = plan(games: [game("God of War.iso", .psp, pspID: "UCUS98737")])
        XCTAssertEqual(batch.items.map(\.plan.destinationURL.lastPathComponent), ["UCUS98737DATA00"], "\(batch.skipped)")
    }

    // MARK: 11. Crash-safe PSP replace

    func testPSPReplaceNeverLeavesTheSlotMissing() throws {
        let gow = game("God of War.iso", .psp, pspID: "UCUS98737")
        let existing = paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: existing.appendingPathComponent("PARAM.SFO"))
        try pspSave("SAVEDATA/UCUS98737DATA00")
        let batch = plan(games: [gow])
        // Moves after the first fail, as if the app died between two of them.
        let flaky = FirstMoveOnlyFileManager()

        _ = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: flaky)

        let param = try Data(contentsOf: existing.appendingPathComponent("PARAM.SFO"))
        XCTAssertEqual(param, Data("PSF".utf8))
        XCTAssertEqual(try leftovers(in: paths.pspSavedataDirectory), [])
    }

    func testLeftoversOfAnInterruptedImportAreCleared() throws {
        let junk = paths.pspSavedataDirectory.appendingPathComponent(".import-\(UUID().uuidString)-UCUS98737DATA00", isDirectory: true)
        try fm.createDirectory(at: junk, withIntermediateDirectories: true)
        try pspSave("SAVEDATA/UCUS98737DATA00")
        let outcome = LibrarySaveImporter().commit(
            plan(games: [game("God of War.iso", .psp, pspID: "UCUS98737")]),
            replaceExisting: true, paths: paths, fileManager: fm
        )
        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertEqual(try leftovers(in: paths.pspSavedataDirectory), [])
    }

    private func leftovers(in directory: URL) throws -> [String] {
        try fm.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".import") }
    }
}

/// Lets the first move through and fails every later one.
private final class FirstMoveOnlyFileManager: FileManager, @unchecked Sendable {
    private var moves = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moves += 1
        guard moves == 1 else { throw CocoaError(.fileWriteUnknown) }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

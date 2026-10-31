// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Second review of the library save import: protection after an interrupted fresh session,
/// one import at a time, contradictory hints, PSP folder bounds while copying, fresh-boot
/// markers on a failed import, hinted systems before names, and a failed PSP swap.
final class SaveImportReviewTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-review-\(UUID().uuidString)", isDirectory: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents", isDirectory: true))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String, count: Int = 8_192) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    private func game(_ name: String, _ system: SystemID, _ id: String? = nil) -> LibraryGame {
        LibraryGame(displayName: name, systemID: system, relativePath: name, pspProductID: id)
    }

    private func plan(_ source: URL, _ games: [LibraryGame], fileManager: FileManager = .default) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([source], fileManager: fileManager), games: games, paths: paths, fileManager: fileManager)
    }

    private func setDate(_ url: URL, _ date: Date) throws {
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: 1. An interrupted fresh session

    func testCrashedPendingStateKeepsTheProtection() throws {
        let target = game("Mario.z64", .n64)
        let old = try SaveStateStore.quickSaveURL(system: .n64, gameID: target.id, paths: paths)
        try Data([1]).write(to: old)
        try setDate(old, Date(timeIntervalSince1970: 1))
        try FreshBoot.mark(target.id, paths: paths)
        // The fresh session died while saving: only a staged state, newer than the import.
        let pending = try SaveStateStore.stagingSaveURL(system: .n64, gameID: target.id, paths: paths)
        try Data([0]).write(to: pending)
        try setDate(pending, Date().addingTimeInterval(60))

        XCTAssertTrue(FreshBoot.isPending(target.id, system: .n64, paths: paths))
    }

    @MainActor
    func testResumeNeverFallsBackToAStateFromBeforeTheImport() async throws {
        let target = game("Mario.z64", .n64)
        let dir = SaveStateStore.quickSaveDirectory(system: .n64, gameID: target.id, paths: paths)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let preImport = dir.appendingPathComponent("quick-1.state")
        try Data([1]).write(to: preImport)
        try setDate(preImport, Date(timeIntervalSince1970: 1))
        let imported = Date(timeIntervalSince1970: 100)
        // Written after the import, but it won't load.
        let newer = try SaveStateStore.quickSaveURL(system: .n64, gameID: target.id, paths: paths)
        try Data([2]).write(to: newer)
        try setDate(newer, Date(timeIntervalSince1970: 200))
        let core = FallbackCore(failing: newer.lastPathComponent)

        let status = await AutoResumeLoader.apply(core: core, system: .n64, gameID: target.id, paths: paths, notBefore: imported)

        XCTAssertNotEqual(status, .loaded)
        XCTAssertNil(core.loaded, "Resumed \(core.loaded?.lastPathComponent ?? "")")
    }

    // MARK: 2. One import at a time

    @MainActor
    func testOverlappingImportsCanNotUnlockLaunchingWhileOneWrites() {
        let sessions = SaveImportSessions()
        let a = try! XCTUnwrap(sessions.beginScan())
        XCTAssertNil(sessions.beginScan(), "a second scan started while the first ran")
        XCTAssertFalse(sessions.allowsImporting)
        XCTAssertTrue(sessions.scanFinished(a))
        XCTAssertTrue(sessions.beginCommit(a, gameOpen: false))
        // A's summary closing mid-write (or any late completion) must not unlock anything.
        sessions.cancel(a)
        XCTAssertFalse(sessions.scanFinished(a))
        XCTAssertEqual(sessions.phase, .committing)
        XCTAssertFalse(sessions.allowsLaunchingGames)
        sessions.end(a)
        XCTAssertTrue(sessions.allowsLaunchingGames)
    }

    @MainActor
    func testALateCompletionOfAnEndedScanIsIgnored() {
        let sessions = SaveImportSessions()
        let a = try! XCTUnwrap(sessions.beginScan())
        sessions.cancel(a)
        let b = try! XCTUnwrap(sessions.beginScan())
        // A's scan returns now: it must not move B on, or end it.
        XCTAssertFalse(sessions.scanFinished(a))
        XCTAssertFalse(sessions.beginCommit(a, gameOpen: false))
        sessions.end(a)
        XCTAssertEqual(sessions.phase, .scanning)
        XCTAssertTrue(sessions.scanFinished(b))
        XCTAssertFalse(sessions.beginCommit(b, gameOpen: true), "wrote while a game was open")
        XCTAssertEqual(sessions.phase, .reviewing)
    }

    // MARK: 3. Contradictory hints

    func testNameAndFolderThatDisagreeChooseNeitherSystem() throws {
        let source = try write("Snes9x/Chrono Trigger.nds.sav", count: 524_288)
        let batch = plan(source.deletingLastPathComponent(), [game("Chrono Trigger.sfc", .snes)])
        XCTAssertTrue(batch.items.isEmpty, "\(batch.items.map(\.sourceName))")
        XCTAssertTrue(try XCTUnwrap(batch.skipped.first?.reason).contains("folder says"))
    }

    // MARK: 4. PSP folder bounds

    func testDirectoriesInsideAPSPFolderCountAgainstItsLimit() throws {
        let slot = root.appendingPathComponent("UCUS98737DATA00")
        try write("UCUS98737DATA00/PARAM.SFO", count: 3)
        for index in 0..<300 {
            try fm.createDirectory(at: slot.appendingPathComponent("empty-\(index)"), withIntermediateDirectories: true)
        }
        XCTAssertTrue(plan(slot, [game("God of War.iso", .psp, "UCUS98737")]).items.isEmpty)
    }

    func testDeeplyNestedPSPFolderIsRefused() throws {
        try write("UCUS98737DATA00/PARAM.SFO", count: 3)
        try write("UCUS98737DATA00/a/b/c/d/e/f/DATA.BIN", count: 3)
        let batch = plan(root.appendingPathComponent("UCUS98737DATA00"), [game("God of War.iso", .psp, "UCUS98737")])
        XCTAssertTrue(batch.items.isEmpty)
    }

    func testPSPFolderThatGrewAfterTheSummaryStopsCopyingEarly() throws {
        let slot = root.appendingPathComponent("UCUS98737DATA00")
        try write("UCUS98737DATA00/PARAM.SFO", count: 3)
        let batch = plan(slot, [game("God of War.iso", .psp, "UCUS98737")])
        XCTAssertEqual(batch.items.count, 1)
        for index in 0..<400 {
            try write("UCUS98737DATA00/F\(index).BIN", count: 1)
        }
        let counting = CountingFileManager()

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: counting)

        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertLessThan(counting.copies, 300, "copied the whole grown folder before checking it")
        XCTAssertFalse(fm.fileExists(atPath: paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00").path))
    }

    func testBatteryFileThatGrewAfterTheSummaryIsNotCopied() throws {
        let source = try write("Zelda.sav")
        let batch = plan(source, [game("Zelda.nes", .nes)])
        XCTAssertEqual(batch.items.count, 1)
        try Data(count: 2 << 20).write(to: source)
        let counting = CountingFileManager()

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: counting)

        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(counting.copies, 0)
    }

    // MARK: 5. Markers on a failed import

    func testFailedValidationLeavesNoFreshBootMarker() throws {
        let target = game("Zelda.gba", .gba)
        let source = try write("Zelda.sav")
        let batch = plan(source, [target])
        try Data().write(to: source)

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertFalse(FreshBoot.isPending(target.id, system: .gba, paths: paths))
    }

    func testFailedInstallRestoresThePreviousMarker() throws {
        let marked = game("Zelda.gba", .gba)
        let unmarked = game("Mario.gba", .gba)
        try FreshBoot.mark(marked.id, at: Date(timeIntervalSince1970: 1_000), paths: paths)
        let before = FreshBoot.marker(marked.id, paths: paths)
        try write("Pick/Zelda.sav")
        try write("Pick/Mario.sav")
        let batch = plan(root.appendingPathComponent("Pick"), [marked, unmarked])
        XCTAssertEqual(batch.items.count, 2)

        // Neither game has a save yet, so installing is a move, and every move fails.
        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths, fileManager: FailingMoveFileManager())

        XCTAssertEqual(outcome.failed.count, 2)
        XCTAssertEqual(FreshBoot.marker(marked.id, paths: paths), before)
        XCTAssertNil(FreshBoot.marker(unmarked.id, paths: paths))
    }

    // MARK: 6. Hinted systems before names

    func testHintedSystemStillMatchesItsNormalizedTitle() throws {
        let source = try write("melonDS/Chrono Trigger.sav", count: 524_288)
        let ds = game("Chrono Trigger (USA).nds", .nds)
        let snes = game("Chrono Trigger.sfc", .snes)
        let batch = plan(source.deletingLastPathComponent(), [snes, ds])
        XCTAssertEqual(batch.items.map(\.game.id), [ds.id], "\(batch.skipped)")
    }

    // MARK: Third review: unreadable parts, bounded metadata lookup, cancellation

    func testUnreadablePSPSubfolderDoesNotInstallAPartialSave() throws {
        let target = game("God of War.iso", .psp, "UCUS98737")
        try write("Pick/UCUS98737DATA00/PARAM.SFO", count: 3)
        let data = try write("Pick/UCUS98737DATA00/DATA/PROGRESS.BIN", count: 16)
        let slot = data.deletingLastPathComponent().deletingLastPathComponent()
        let batch = plan(slot, [target])
        XCTAssertEqual(batch.items.count, 1)
        let dest = paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00")
        try fm.createDirectory(at: dest.appendingPathComponent("DATA"), withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: dest.appendingPathComponent("PARAM.SFO"))
        let progress = dest.appendingPathComponent("DATA/PROGRESS.BIN")
        try Data("OLD PROGRESS".utf8).write(to: progress)
        // The subfolder can no longer be read when the import runs.
        let blocked = data.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }

        let outcome = LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths)

        XCTAssertTrue(outcome.imported.isEmpty, "the unreadable subfolder was left out silently")
        XCTAssertEqual(try? Data(contentsOf: progress), Data("OLD PROGRESS".utf8))
    }

    func testFindingPARAMSFOStaysWithinTheEntryBudget() throws {
        let slot = root.appendingPathComponent("UCUS98737DATA00")
        try write("UCUS98737DATA00/README.TXT", count: 3)
        for index in 0..<300 {
            try write("UCUS98737DATA00/F\(index).BIN", count: 1)
        }
        let recording = ListingFileManager()

        XCTAssertThrowsError(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: recording))
        XCTAssertNil(SaveGameImporter.paramSFO(in: slot, fileManager: recording))

        XCTAssertLessThanOrEqual(recording.largestListing, SaveGameImporter.pspFolderMaxEntries)
    }

    func testCancelledScanFindsNothing() async throws {
        try write("Pick/Zelda.sav")
        let pick = root.appendingPathComponent("Pick")
        let scan = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return SaveFolderScanner.scan([pick])
        }.value
        XCTAssertTrue(scan.candidates.isEmpty)
    }

    func testCancelledPlanAndCommitWriteNothing() async throws {
        let zelda = game("Zelda.gba", .gba)
        let source = try write("Zelda.sav")
        let batch = plan(source, [zelda])
        XCTAssertEqual(batch.items.count, 1)
        let paths = self.paths!
        let games = [zelda]

        let (replanned, outcome) = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let replanned = LibrarySaveImporter().plan(SaveFolderScanner.scan([source]), games: games, paths: paths)
            return (replanned, LibrarySaveImporter().commit(batch, replaceExisting: true, paths: paths))
        }.value

        XCTAssertTrue(replanned.items.isEmpty)
        XCTAssertTrue(outcome.imported.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: paths.sramURL(forRelativeROMPath: zelda.relativePath).path))
    }

    // MARK: PSP swap failure

    func testFailedSwapLeavesTheOldSlotAndNoLeftovers() throws {
        let target = game("God of War.iso", .psp, "UCUS98737")
        let existing = paths.pspSavedataDirectory.appendingPathComponent("UCUS98737DATA00", isDirectory: true)
        try fm.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: existing.appendingPathComponent("PARAM.SFO"))
        let slot = root.appendingPathComponent("Pick/UCUS98737DATA00")
        try write("Pick/UCUS98737DATA00/PARAM.SFO", count: 3)
        let item = try XCTUnwrap(plan(slot, [target]).items.first)

        XCTAssertThrowsError(try SaveGameImporter().commitImport(
            plan: item.plan,
            from: slot,
            overwrite: true,
            swap: { _, _ in throw SaveGameImportError.copyFailed("injected") }
        ))

        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("PARAM.SFO")), Data("OLD".utf8))
        let left = try fm.contentsOfDirectory(atPath: paths.pspSavedataDirectory.path).filter { $0.hasPrefix(".import") }
        XCTAssertEqual(left, [])
    }
}

private final class ListingFileManager: FileManager, @unchecked Sendable {
    private(set) var largestListing = 0

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        let names = try super.contentsOfDirectory(atPath: path)
        largestListing = max(largestListing, names.count)
        return names
    }
}

private final class CountingFileManager: FileManager, @unchecked Sendable {
    private(set) var copies = 0

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copies += 1
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

private final class FailingMoveFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

/// Loads any state except the one named `failing`.
private final class FallbackCore: TestEmulatorCore, @unchecked Sendable {
    let systemID = SystemID.n64
    let coreName = "FallbackCore"
    let supportsSaveState = true
    let supportsFastForward = false
    private let failing: String
    private(set) var loaded: URL?

    init(failing: String) { self.failing = failing }

    func start() {}
    func pause() {}
    func resume() {}
    func stop() {}
    func saveState(to url: URL) async throws {}
    func setFastForward(_ enabled: Bool) {}
    func loadState(from url: URL) async throws {
        if url.lastPathComponent == failing { throw CocoaError(.fileReadCorruptFile) }
        loaded = url
    }
}

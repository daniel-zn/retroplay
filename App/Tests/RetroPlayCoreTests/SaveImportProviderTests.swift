// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// File Provider behaviour (each folder coordinated on its own, cancellable waits), PSP save
/// name spellings on a case-sensitive file system like iOS's, and folder names that don't
/// prove anything about what's inside.
///
/// The case tests need a case-sensitive volume: they use `RETROPLAY_CASE_SENSITIVE_ROOT`, or
/// one mounted at /tmp/retroplay-review-case-mount, or the temporary folder when it's
/// case-sensitive, and are skipped otherwise.
final class SaveImportProviderTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!
    private var caseRoot: URL?

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-provider-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        if let caseRoot { try? fm.removeItem(at: caseRoot) }
    }

    /// Switches `root` and `paths` to a case-sensitive folder, or skips the test.
    private func useCaseSensitiveRoot() throws {
        let candidates = [
            ProcessInfo.processInfo.environment["RETROPLAY_CASE_SENSITIVE_ROOT"].map { URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: "/tmp/retroplay-review-case-mount"),
            fm.temporaryDirectory,
        ].compactMap { $0 }
        for base in candidates where fm.fileExists(atPath: base.path) {
            let probe = base.appendingPathComponent("rp-case-\(UUID().uuidString)", isDirectory: true)
            guard (try? fm.createDirectory(at: probe, withIntermediateDirectories: true)) != nil else { continue }
            try Data().write(to: probe.appendingPathComponent("a"))
            if !fm.fileExists(atPath: probe.appendingPathComponent("A").path) {
                caseRoot = probe
                root = probe
                paths = SavePaths(documentsURL: probe.appendingPathComponent("Documents"))
                try paths.ensureDirectories()
                return
            }
            try? fm.removeItem(at: probe)
        }
        throw XCTSkip("needs a case-sensitive volume")
    }

    @discardableResult
    private func write(_ relative: String, count: Int = 8_192, fill: UInt8 = 7) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: count).write(to: url)
        return url
    }

    private func slot(_ name: String, fill: UInt8 = 7) throws -> URL {
        let param = try write(name + "/PARAM.SFO", count: 3, fill: fill)
        try write(name + "/DATA.BIN", count: 16, fill: fill)
        return param.deletingLastPathComponent()
    }

    private var ff4: LibraryGame {
        LibraryGame(displayName: "FF4", systemID: .psp, relativePath: "FF4.iso", pspProductID: "ULUS10560")
    }

    private func batch(_ source: URL) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([source]), games: [ff4], paths: paths)
    }

    // MARK: 1. Each folder coordinated on its own

    func testEachSubfolderIsCoordinatedSoALazyProviderFillsIt() throws {
        let folder = root.appendingPathComponent("Pick/Inner")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let presenter = LazyFolderPresenter(folder)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let result = SaveFolderScanner.scan([root.appendingPathComponent("Pick")])

        XCTAssertEqual(result.candidates.map(\.url.lastPathComponent), ["Zelda.sav"], "\(result.skipped)")
    }

    func testFolderThatCanBeListedButNotSearchedIsOneReadError() throws {
        let folder = root.appendingPathComponent("ReadOnly")
        for index in 0..<300 {
            try write("ReadOnly/\(index).sav", count: 1)
        }
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: folder.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        let result = SaveFolderScanner.scan([folder], limits: SaveScanLimits(maxEntries: 5))

        XCTAssertEqual(result.skipped.count, 1, "\(result.skipped.prefix(3))")
        XCTAssertFalse(result.truncated)
    }

    // MARK: 2. Spellings of one PSP slot

    func testTheGamesMixedCaseSpellingWinsOverANewerUppercaseCopy() throws {
        try useCaseSensitiveRoot()
        let mixed = try slot("Pick/ULUS10560System", fill: 1)
        let upper = try slot("Pick/ULUS10560SYSTEM", fill: 2)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: mixed.appendingPathComponent("PARAM.SFO").path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: upper.appendingPathComponent("PARAM.SFO").path)

        let result = batch(root.appendingPathComponent("Pick"))

        XCTAssertEqual(result.items.map(\.plan.destinationURL.lastPathComponent), ["ULUS10560System"])
        XCTAssertNotNil(result.skipped.first { $0.name.hasSuffix("ULUS10560SYSTEM") }, "\(result.skipped)")
    }

    func testTwoMixedCaseSpellingsOfOneSlotAreReportedNotGuessed() throws {
        try useCaseSensitiveRoot()
        try slot("Pick/ULUS10560System")
        try slot("Pick/ULUS10560system")

        let result = batch(root.appendingPathComponent("Pick"))

        XCTAssertTrue(result.items.isEmpty, "\(result.items.map(\.sourceName))")
        XCTAssertEqual(result.skipped.count, 2, "\(result.skipped)")
    }

    func testExactDestinationLeavesAnotherSpellingAlone() throws {
        try useCaseSensitiveRoot()
        let upper = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560SYSTEM")
        let exact = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560System")
        for (url, bytes) in [(upper, Data("UPPER".utf8)), (exact, Data("EXACT".utf8))] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try bytes.write(to: url.appendingPathComponent("PARAM.SFO"))
        }
        let source = try slot("Pick/ULUS10560System", fill: 9)

        let outcome = LibrarySaveImporter().commit(batch(source), replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.imported.count, 1)
        XCTAssertEqual(try Data(contentsOf: upper.appendingPathComponent("PARAM.SFO")), Data("UPPER".utf8))
        XCTAssertEqual(try Data(contentsOf: exact.appendingPathComponent("PARAM.SFO")), Data(repeating: 9, count: 3))
    }

    // MARK: 3. No rename unless the install succeeds

    func testFailedSwapLeavesTheOldSlotUnderItsOldName() throws {
        try useCaseSensitiveRoot()
        let old = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560SYSTEM")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: old.appendingPathComponent("PARAM.SFO"))
        let source = try slot("Pick/ULUS10560System")
        let item = try XCTUnwrap(batch(source).items.first)

        XCTAssertThrowsError(try SaveGameImporter().commitImport(
            plan: item.plan, from: source, overwrite: true,
            swap: { _, _ in throw CocoaError(.fileWriteUnknown) }
        ))

        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("PARAM.SFO")), Data("OLD".utf8))
        XCTAssertFalse(fm.fileExists(atPath: item.plan.destinationURL.path))
    }

    func testReimportUnderTheGamesSpellingReplacesTheUppercaseSlot() throws {
        try useCaseSensitiveRoot()
        let old = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560SYSTEM")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: old.appendingPathComponent("PARAM.SFO"))
        try slot("Pick/ULUS10560System", fill: 9)

        let outcome = LibrarySaveImporter().commit(batch(root.appendingPathComponent("Pick")), replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        let names = try fm.contentsOfDirectory(atPath: paths.pspSavedataDirectory.path).filter { !$0.hasPrefix(".") }
        XCTAssertEqual(names, ["ULUS10560System"])
    }

    // MARK: 4. Folder names alone don't skip anything

    func testSavesInAFolderNamedPCAreStillFound() throws {
        try write("PC/RetroArch/saves/mGBA/Zelda.sav")
        let result = SaveFolderScanner.scan([root.appendingPathComponent("PC")])
        XCTAssertEqual(result.candidates.count, 1, "\(result.skipped)")
    }

    func testOtherSystemsFilesAreLabelledOneByOne() throws {
        try write("Backups/Wii U/Breath of the Wild/game_data.sav", count: 4_096)
        let batch = LibrarySaveImporter().plan(
            SaveFolderScanner.scan([root.appendingPathComponent("Backups")]),
            games: [LibraryGame(displayName: "Zelda", systemID: .gba, relativePath: "Zelda.gba")],
            paths: paths
        )
        // No folder name proves it isn't a cartridge save: its name says it's for no game here.
        XCTAssertEqual(batch.skipped.map(\.name), ["Backups/Wii U/Breath of the Wild/game_data.sav"])
    }

    // MARK: 5. Stop cancels a coordinated wait

    func testCancellingTheScanInterruptsAPendingCoordinatedRead() async throws {
        let save = try write("Blocked/Zelda.sav")
        let started = expectation(description: "presenter asked")
        let completed = expectation(description: "cancelled scan returned")
        let release = DispatchSemaphore(value: 0)
        let presenter = BlockingPresenter(save.deletingLastPathComponent(), started, release)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }
        let folder = save.deletingLastPathComponent()
        let task = Task.detached {
            let result = SaveFolderScanner.scan([folder])
            completed.fulfill()
            return result
        }

        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await fulfillment(of: [completed], timeout: 2)
        release.signal()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
    }
}

/// A provider that only fills its folder when a coordinated read asks for it.
private final class LazyFolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let folder: URL
    let queue = OperationQueue()

    init(_ folder: URL) {
        self.folder = folder
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    var presentedItemURL: URL? { folder }
    var presentedItemOperationQueue: OperationQueue { queue }

    func savePresentedItemChanges(completionHandler: @escaping (Error?) -> Void) {
        do {
            try Data(count: 8_192).write(to: folder.appendingPathComponent("Zelda.sav"))
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

/// A provider that keeps a coordinated read waiting until released.
private final class BlockingPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let folder: URL
    let queue = OperationQueue()
    let started: XCTestExpectation
    let release: DispatchSemaphore

    init(_ folder: URL, _ started: XCTestExpectation, _ release: DispatchSemaphore) {
        self.folder = folder
        self.started = started
        self.release = release
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    var presentedItemURL: URL? { folder }
    var presentedItemOperationQueue: OperationQueue { queue }

    func savePresentedItemChanges(completionHandler: @escaping (Error?) -> Void) {
        started.fulfill()
        release.wait()
        completionHandler(nil)
    }
}

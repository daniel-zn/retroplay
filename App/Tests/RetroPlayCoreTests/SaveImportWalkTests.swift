// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// The one folder walk (library scan, PSP check and copy): limits counted for roots, entries
/// and every candidate; each PSP subfolder coordinated; one cancel flag; installs that can't
/// lose the old save; no Vita verdict from a folder name alone.
final class SaveImportWalkTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!
    private var caseRoot: URL?

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-walk-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
        if let caseRoot { try? fm.removeItem(at: caseRoot) }
    }

    @discardableResult
    private func write(_ path: String, count: Int = 8_192, fill: UInt8 = 7) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: count).write(to: url)
        return url
    }

    private var ff4: LibraryGame {
        LibraryGame(displayName: "FF4", systemID: .psp, relativePath: "FF4.iso", pspProductID: "ULUS10560")
    }

    private func batch(_ source: URL) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([source]), games: [ff4], paths: paths)
    }

    // MARK: 1. PSP subfolders coordinated, all or nothing

    func testPSPCopyCoordinatesALazyDataSubfolder() throws {
        let source = try write("Pick/ULUS10560System/PARAM.SFO", count: 3).deletingLastPathComponent()
        let data = source.appendingPathComponent("DATA")
        try fm.createDirectory(at: data, withIntermediateDirectories: true)
        let presenter = LazyPayload(data)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }
        let planned = batch(source)
        let dest = try XCTUnwrap(planned.items.first?.plan.destinationURL)
        try fm.createDirectory(at: dest.appendingPathComponent("DATA"), withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: dest.appendingPathComponent("PARAM.SFO"))
        try Data("OLD PROGRESS".utf8).write(to: dest.appendingPathComponent("DATA/PROGRESS.BIN"))

        let outcome = LibrarySaveImporter().commit(planned, replaceExisting: true, paths: paths)

        XCTAssertEqual(outcome.imported.count, 1, "\(outcome.failed)")
        XCTAssertEqual(try? Data(contentsOf: dest.appendingPathComponent("DATA/PROGRESS.BIN")), Data("NEW PROGRESS".utf8))
    }

    // MARK: 2. No step after the install that can lose the old save

    func testAFailedInstallUnderTheGamesSpellingKeepsTheOldSlot() throws {
        try useCaseSensitiveRoot()
        let old = paths.pspSavedataDirectory.appendingPathComponent("ULUS10560SYSTEM")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("OLD".utf8).write(to: old.appendingPathComponent("PARAM.SFO"))
        let source = try write("Pick/ULUS10560System/PARAM.SFO", count: 3).deletingLastPathComponent()
        let item = try XCTUnwrap(batch(source).items.first)

        // The install is one move into the game's spelling; it fails here.
        XCTAssertThrowsError(try SaveGameImporter().commitImport(
            plan: item.plan, from: source, overwrite: true, fileManager: FailingMoveFileManager()
        ))

        XCTAssertEqual(try Data(contentsOf: old.appendingPathComponent("PARAM.SFO")), Data("OLD".utf8))
        let names = try fm.contentsOfDirectory(atPath: paths.pspSavedataDirectory.path)
        XCTAssertEqual(names, ["ULUS10560SYSTEM"])
    }

    // MARK: 4. Limits

    func testPSPSlotsCountAgainstTheCandidateLimit() throws {
        for index in 0..<10 {
            try write(String(format: "Pick/ULUS10560DATA%02d/PARAM.SFO", index), count: 3)
        }
        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Pick")], limits: SaveScanLimits(maxCandidates: 1))
        XCTAssertEqual(scan.candidates.count, 1)
        XCTAssertTrue(scan.truncated)
    }

    func testAWideFolderIsListedOnlyUpToTheBudget() throws {
        for index in 0..<300 {
            try write("Pick/F\(index).sav", count: 1)
        }
        let counting = ListingFileManager()
        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Pick")], limits: SaveScanLimits(maxEntries: 5), fileManager: counting)
        XCTAssertTrue(scan.truncated)
        XCTAssertLessThanOrEqual(counting.largest, 6)
        XCTAssertLessThanOrEqual(scan.ignoredFiles + scan.candidates.count + scan.skipped.count, 5)
    }

    func testPickedRootsCountAgainstTheBudget() throws {
        let roots = try (0..<20).map { index -> URL in
            let url = root.appendingPathComponent("Empty\(index)")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let counting = ListingFileManager()
        let scan = SaveFolderScanner.scan(roots, limits: SaveScanLimits(maxEntries: 1), fileManager: counting)
        XCTAssertLessThanOrEqual(counting.listings, 1)
        XCTAssertTrue(scan.truncated)
    }

    // MARK: 5. One cancel flag, seen during a read

    func testCancellingEndsAReadWhoseBodyIsStillWorking() throws {
        let folder = try write("Slow/Zelda.sav").deletingLastPathComponent()
        let cancellation = ImportCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancellation.cancel() }
        let started = Date()

        XCTAssertThrowsError(try CoordinatedRead.run(folder, cancellation) { _ in
            // Busy I/O that only stops when it sees the flag.
            while !cancellation.isCancelled { Thread.sleep(forTimeInterval: 0.01) }
            try cancellation.check()
        }) { XCTAssertTrue($0 is CancellationError, "\($0)") }

        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testACancelledScanStopsBetweenEntries() throws {
        try write("Pick/A/Zelda.sav")
        let cancellation = ImportCancellation()
        cancellation.cancel()
        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Pick")], cancellation: cancellation)
        XCTAssertTrue(scan.cancelled)
        XCTAssertTrue(scan.candidates.isEmpty)
    }

    // MARK: 6. A Vita-looking name alone proves nothing

    func testAVitaTitleIDNameWithoutSceSysDoesNotHideASave() throws {
        try write("Pick/PCSA00017/Zelda.sav")
        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Pick")])
        XCTAssertEqual(scan.candidates.count, 1)
        XCTAssertEqual(scan.otherSystemSaves, 0)
    }

    // MARK: Helpers

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
}

private final class FailingMoveFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private final class ListingFileManager: FileManager, @unchecked Sendable {
    private(set) var largest = 0
    private(set) var listings = 0

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        let all = try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
        largest = max(largest, all.count)
        listings += 1
        return all
    }
}

/// A provider that only fills its folder when a coordinated read asks for it.
private final class LazyPayload: NSObject, NSFilePresenter, @unchecked Sendable {
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
            try Data("NEW PROGRESS".utf8).write(to: folder.appendingPathComponent("PROGRESS.BIN"))
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

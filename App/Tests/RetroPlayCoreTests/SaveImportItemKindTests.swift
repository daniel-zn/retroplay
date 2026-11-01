// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// A File Provider (an SMB share in Files, iCloud Drive) may leave an entry's type out of its
/// resource values, or report it wrong. A folder taken for a file was passed over without a
/// word: "No saves in this folder" for a folder holding a PSP save (seen on a device). These
/// model that with `FolderWalk.reported`, and check that a scan finding nothing says what it
/// looked at.
final class SaveImportItemKindTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-kind-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        FolderWalk.reported = nil
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String, count: Int = 16) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    /// Daniel's folder: 2026-10-30/UCUS98648PROFILE00 (ATV Offroad Fury Pro).
    private func atvSave() throws -> URL {
        for file in ["PARAM.SFO", "PROFILE.BIN", "ICON0.PNG", "PIC1.PNG"] {
            try write("Pick/2026-10-30/UCUS98648PROFILE00/\(file)")
        }
        return root.appendingPathComponent("Pick/2026-10-30")
    }

    private let atv = LibraryGame(displayName: "ATV Offroad Fury Pro", systemID: .psp, relativePath: "ATV.iso", pspProductID: "UCUS98648")

    private func plan(_ picked: URL) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan([picked]), games: [atv], paths: paths)
    }

    // MARK: The type left out or wrong

    func testAFolderWhoseTypeTheProviderLeavesOutIsStillLookedInto() throws {
        let picked = try atvSave()
        FolderWalk.reported = { url in
            url.lastPathComponent == "UCUS98648PROFILE00" ? FolderWalk.Reported() : nil
        }
        XCTAssertEqual(plan(picked).items.map(\.game.id), [atv.id])
    }

    func testAFolderTheProviderCallsAFileIsCheckedAgainstTheFileSystem() throws {
        let picked = try atvSave()
        FolderWalk.reported = { url in
            url.lastPathComponent == "UCUS98648PROFILE00"
                ? FolderWalk.Reported(isDirectory: false, isRegularFile: true) : nil
        }
        XCTAssertEqual(plan(picked).items.map(\.game.id), [atv.id])
    }

    func testAPickedFolderTheProviderCallsAFileIsStillWalked() throws {
        let picked = try atvSave()
        FolderWalk.reported = { url in
            url.lastPathComponent == "2026-10-30" ? FolderWalk.Reported(isDirectory: false, isRegularFile: true) : nil
        }
        XCTAssertEqual(plan(picked).items.map(\.game.id), [atv.id])
    }

    func testAnEntryNothingReportsATypeForIsLookedIntoNotIgnored() throws {
        let unknown = root.appendingPathComponent("Somewhere/Unknown")
        XCTAssertEqual(FolderWalk.item(unknown, reported: FolderWalk.Reported()).kind, .folder)
        let file = try write("plain.bin")
        XCTAssertEqual(FolderWalk.item(file, reported: FolderWalk.Reported()).kind, .file)
    }

    // MARK: Saying what was looked at

    func testAScanThatFindsNothingSaysWhatItLookedAt() throws {
        try write("Pick/2026-10-30/readme.txt")
        try fm.createDirectory(at: root.appendingPathComponent("Pick/2026-10-30/Empty"), withIntermediateDirectories: true)

        let batch = plan(root.appendingPathComponent("Pick/2026-10-30"))

        XCTAssertTrue(batch.items.isEmpty)
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(batch.notes, [
            "“2026-10-30”: 1 folder, 1 file",
            "“2026-10-30/readme.txt”: not a save file",
            "“2026-10-30/Empty”: 0 folders, 0 files",
        ])
    }

    func testAPSPFolderWithoutPARAMSFOSaysHowManyEntriesItListed() throws {
        try write("Pick/2026-10-30/UCUS98648PROFILE00/PROFILE.BIN")
        try write("Pick/2026-10-30/UCUS98648PROFILE00/ICON0.PNG")

        let batch = plan(root.appendingPathComponent("Pick/2026-10-30"))

        let reason = try XCTUnwrap(batch.skipped.first { $0.name.hasSuffix("UCUS98648PROFILE00") }?.reason)
        XCTAssertTrue(reason.contains("PARAM.SFO"), reason)
        XCTAssertTrue(reason.contains("(2 entries listed)"), reason)
    }

    func testNotesStopAtTheirLimit() throws {
        for index in 0..<20 {
            try write("Pick/notes/file\(index).txt")
        }
        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Pick/notes")])
        XCTAssertEqual(scan.notes.count, SaveFolderScanner.maxNotes + 1)
        XCTAssertEqual(scan.notes.last, "…")
    }
}

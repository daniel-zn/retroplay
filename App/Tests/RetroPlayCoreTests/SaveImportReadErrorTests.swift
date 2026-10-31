// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Folders the scan can't fully read (a File Provider folder not materialised, no permission)
/// are reported with what failed, never skipped silently, so "No saves" isn't shown for a
/// folder that couldn't be read.
final class SaveImportReadErrorTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var locked: [URL] = []

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-save-read-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for url in locked { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ path: String, count: Int = 8_192) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    private func lock(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        locked.append(url)
    }

    func testUnreadableSubfolderIsReportedAndTheRestStillFound() throws {
        try write("Saves/GBA/Zelda/2026-10-30/Zelda.sav")
        try write("Saves/GBA/Metroid/2026-10-30/Metroid.sav")
        try lock("Saves/GBA/Metroid")

        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Saves")])

        XCTAssertEqual(scan.candidates.map(\.url.lastPathComponent), ["Zelda.sav"])
        let error = try XCTUnwrap(scan.skipped.first { $0.name.hasSuffix("GBA/Metroid") }, "\(scan.skipped)")
        XCTAssertTrue(error.reason.hasPrefix("Couldn't read it"), error.reason)
    }

    func testUnreadablePickedFolderIsReported() throws {
        try write("Saves/GBA/Zelda.sav")
        try lock("Saves")

        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Saves")])

        XCTAssertTrue(scan.candidates.isEmpty)
        XCTAssertEqual(scan.skipped.count, 1, "\(scan.skipped)")
        let reason = scan.skipped.first?.reason ?? ""
        XCTAssertTrue(reason.hasPrefix("Couldn't read it"), reason)
    }

    func testPickedItemWhoseDetailsCanNotBeReadIsReportedNotTreatedAsAFile() throws {
        try write("Outer/Inner/Zelda.sav")
        try lock("Outer")

        let scan = SaveFolderScanner.scan([root.appendingPathComponent("Outer/Inner")])

        XCTAssertEqual(scan.ignoredFiles, 0)
        XCTAssertEqual(scan.skipped.map(\.name), ["Inner"])
        let reason = scan.skipped.first?.reason ?? ""
        XCTAssertTrue(reason.hasPrefix("Couldn't read it"), reason)
    }

    func testSavesAFewFoldersDeepAreFound() throws {
        try write("Documents/A/B/C/Zelda.sav")
        let batch = LibrarySaveImporter().plan(
            SaveFolderScanner.scan([root.appendingPathComponent("Documents")]),
            games: [LibraryGame(displayName: "Zelda", systemID: .gba, relativePath: "Zelda.gba")],
            paths: SavePaths(documentsURL: root.appendingPathComponent("Sandbox"))
        )
        XCTAssertEqual(batch.items.map(\.sourceName), ["Documents/A/B/C/Zelda.sav"], "\(batch.skipped)")
    }
}

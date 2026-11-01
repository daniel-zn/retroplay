// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// On a device, a folder in On My iPhone or iCloud Drive can list nothing through the bulk
/// listing (its contents aren't on disk yet) though it holds entries: a picked PSP slot then
/// read as "must include PARAM.SFO (0 entries listed)", and a folder above it found nothing.
/// Such a folder is read again with a plain directory read, and if that lists nothing too,
/// it's reported, not taken for empty. Also: a pick spelled through /var or /private/var.
final class SaveImportEmptyListingTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-empty-listing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        FolderWalk.bulkListing = nil
        FolderWalk.plainListing = nil
        DirectoryMetadata.stat = nil
        try? fm.removeItem(at: root)
    }

    private var atv: LibraryGame {
        LibraryGame(displayName: "ATV Offroad Fury Pro", systemID: .psp, relativePath: "ATV.iso", pspProductID: "UCUS98648")
    }

    /// Pick/PSP/SAVEDATA/UCUS98648PROFILE00 with the four files a real slot holds.
    private func makeSlot() throws -> URL {
        let slot = root.appendingPathComponent("Pick/PSP/SAVEDATA/UCUS98648PROFILE00", isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        for (name, size) in [("PARAM.SFO", 4_096), ("PROFILE.BIN", 20_000), ("ICON0.PNG", 900), ("PIC1.PNG", 3_000)] {
            try Data(repeating: 1, count: size).write(to: slot.appendingPathComponent(name))
        }
        return slot
    }

    private func batch(_ picks: [URL]) -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan(picks), games: [atv], paths: paths)
    }

    /// The bulk listing lists nothing for folders named in `names`.
    private func bulkListsNothing(for names: Set<String>) {
        FolderWalk.bulkListing = { url in names.contains(url.lastPathComponent) ? [] : nil }
    }

    func testAPickedSlotTheBulkListingMissesIsReadAgainAndFound() throws {
        let slot = try makeSlot()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        let found = batch([slot])
        XCTAssertEqual(found.items.map(\.game.displayName), ["ATV Offroad Fury Pro"], "\(found.skipped)")
        XCTAssertEqual(found.skipped, [])
    }

    func testAFolderAboveTheSlotFindsItWhenTheBulkListingMissesEveryFolder() throws {
        _ = try makeSlot()
        bulkListsNothing(for: ["Pick", "PSP", "SAVEDATA", "UCUS98648PROFILE00"])
        let found = batch([root.appendingPathComponent("Pick", isDirectory: true)])
        XCTAssertEqual(found.items.map(\.game.displayName), ["ATV Offroad Fury Pro"], "\(found.skipped) \(found.notes)")
    }

    func testAFolderThatListsNothingButHoldsEntriesIsReported() throws {
        _ = try makeSlot()
        FolderWalk.bulkListing = { $0.lastPathComponent == "SAVEDATA" ? [] : nil }
        FolderWalk.plainListing = { $0.lastPathComponent == "SAVEDATA" ? [] : nil }
        let found = batch([root.appendingPathComponent("Pick", isDirectory: true)])
        XCTAssertEqual(found.items, [])
        let row = try XCTUnwrap(found.skipped.first { $0.name == "Pick/PSP/SAVEDATA" }, "\(found.skipped)")
        XCTAssertTrue(row.reason.contains("Files listed nothing in it, but it holds 1 item"), row.reason)
    }

    func testADatalessFolderThatListsNothingIsReported() throws {
        let slot = try makeSlot()
        FolderWalk.bulkListing = { $0 == slot ? [] : nil }
        FolderWalk.plainListing = { $0 == slot ? [] : nil }
        DirectoryMetadata.stat = { $0 == slot ? (links: 2, dataless: true) : nil }
        let found = batch([slot])
        XCTAssertEqual(found.items, [])
        XCTAssertTrue(found.skipped.first?.reason.contains("contents aren't on this iPhone yet") == true, "\(found.skipped)")
    }

    func testAnEmptyFolderIsStillJustEmpty() throws {
        let empty = root.appendingPathComponent("Pick/Empty", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        let found = batch([empty])
        XCTAssertEqual(found.items, [])
        XCTAssertEqual(found.skipped, [])
    }

    /// A device's picks and listings mix /var/… and /private/var/… (/var is a link): the
    /// walk goes by what each listing returns, so either spelling finds the slot.
    func testAPickSpelledThroughTheVarLinkOrItsTargetFindsTheSlot() throws {
        _ = try makeSlot()
        let pick = root.appendingPathComponent("Pick", isDirectory: true)
        // `resolvingSymlinksInPath` hands back /var/… itself, so both spellings are made here.
        let path = pick.path
        // Only where the temporary folder sits under the /var link (macOS, a device); the
        // Simulator keeps it under the Mac user's folder.
        guard path.hasPrefix("/private/var/") || path.hasPrefix("/var/") else {
            throw XCTSkip("the temporary folder isn't under the /var link here: \(path)")
        }
        let short = path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
        let spellings = [URL(fileURLWithPath: short, isDirectory: true), URL(fileURLWithPath: "/private" + short, isDirectory: true)]
        for spelling in spellings {
            let found = batch([spelling])
            XCTAssertEqual(found.items.map(\.game.displayName), ["ATV Offroad Fury Pro"], "\(spelling.path): \(found.skipped)")
        }
    }
}

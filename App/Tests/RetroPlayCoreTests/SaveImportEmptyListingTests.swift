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
    private var locked: URL?

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rp-empty-listing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        // An unreadable folder made for a test, readable again so it can be removed.
        if let locked { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        FolderWalk.bulkListing = nil
        FolderWalk.plainListing = nil
        FolderWalk.pathListing = nil
        FolderWalk.uncoordinatedListing = nil
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
        FolderWalk.pathListing = { $0.lastPathComponent == "SAVEDATA" ? [] : nil }
        FolderWalk.uncoordinatedListing = { $0.lastPathComponent == "SAVEDATA" ? [] : nil }
        let found = batch([root.appendingPathComponent("Pick", isDirectory: true)])
        XCTAssertEqual(found.items, [])
        let row = try XCTUnwrap(found.skipped.first { $0.name == "Pick/PSP/SAVEDATA" }, "\(found.skipped)")
        XCTAssertTrue(row.reason.contains("Files listed nothing in it, but it holds 1 item"), row.reason)
    }

    func testADatalessFolderThatListsNothingIsReported() throws {
        let slot = try makeSlot()
        FolderWalk.bulkListing = { $0 == slot ? [] : nil }
        FolderWalk.plainListing = { $0 == slot ? [] : nil }
        FolderWalk.pathListing = { $0 == slot ? [] : nil }
        FolderWalk.uncoordinatedListing = { $0 == slot ? [] : nil }
        DirectoryMetadata.stat = { $0 == slot ? (links: 2, dataless: true) : nil }
        // Its files aren't there to open by name either.
        try fm.removeItem(at: slot.appendingPathComponent("PARAM.SFO"))
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

    // MARK: Folders whose metadata doesn't count entries (SMB, File Provider)

    /// An SMB share or File Provider folder reports a link count of 1 or 2 whatever it holds.
    private func metadataCountsNothing() {
        DirectoryMetadata.stat = { _ in (links: 2, dataless: false) }
    }

    func testOnAShareTheEnumeratorsEmptyListingIsCheckedAgainstAPlainRead() throws {
        let slot = try makeSlot()
        metadataCountsNothing()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        let found = batch([slot])
        XCTAssertEqual(found.items.map(\.game.displayName), ["ATV Offroad Fury Pro"], "\(found.skipped)")
    }

    func testOnAShareTheOriginalURLIsListedOutsideTheCoordinatorToo() throws {
        let slot = try makeSlot()
        metadataCountsNothing()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        FolderWalk.plainListing = { $0.lastPathComponent == "UCUS98648PROFILE00" ? [] : nil }
        FolderWalk.pathListing = { $0.lastPathComponent == "UCUS98648PROFILE00" ? [] : nil }
        let found = batch([slot])
        XCTAssertEqual(found.items.map(\.game.displayName), ["ATV Offroad Fury Pro"], "\(found.skipped)")
    }

    func testAFolderEveryListingAgreesIsEmptyIsJustEmpty() throws {
        let empty = root.appendingPathComponent("Pick/Empty", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        metadataCountsNothing()
        let found = batch([empty])
        XCTAssertEqual(found.items, [])
        XCTAssertEqual(found.skipped, [])
    }

    // MARK: Listings that fail aren't empty folders

    func testAFolderNoListingCanReadIsAnErrorNotEmpty() throws {
        // The enumerator lists nothing (as on the device) and every other listing is refused
        // by the file system: that's a read failure, not a slot without PARAM.SFO.
        let slot = try makeSlot()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: slot.path)
        locked = slot
        XCTAssertThrowsError(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: fm)) { error in
            let text = error.localizedDescription
            XCTAssertFalse(text.contains("PARAM.SFO"), "a refused listing read as an empty slot: \(text)")
            XCTAssertTrue(text.contains("Couldn't list UCUS98648PROFILE00"), text)
            XCTAssertTrue(text.lowercased().contains("permission denied"), text)
        }
        let found = batch([slot])
        XCTAssertEqual(found.items, [])
        let reason = try XCTUnwrap(found.skipped.first?.reason)
        XCTAssertTrue(reason.contains("Couldn't list UCUS98648PROFILE00"), reason)
    }

    func testEveryMethodAndItsErrorIsNamed() throws {
        let slot = try makeSlot()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        let denied: @Sendable (URL) throws -> [URL]? = { url in
            guard url.lastPathComponent == "UCUS98648PROFILE00" else { return nil }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                          userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        }
        FolderWalk.plainListing = denied
        FolderWalk.pathListing = denied
        FolderWalk.uncoordinatedListing = denied
        XCTAssertThrowsError(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: fm)) { error in
            XCTAssertTrue(error.localizedDescription.contains(
                "Couldn't list UCUS98648PROFILE00: enumerator 0, contents Operation not permitted, path Operation not permitted, picked URL Operation not permitted"
            ), error.localizedDescription)
        }
    }

    func testOneMethodFailingAnotherFindingEntriesUsesTheEntries() throws {
        let slot = try makeSlot()
        bulkListsNothing(for: ["UCUS98648PROFILE00"])
        FolderWalk.plainListing = { url in
            guard url.lastPathComponent == "UCUS98648PROFILE00" else { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        }
        XCTAssertNoThrow(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: fm))
    }
}

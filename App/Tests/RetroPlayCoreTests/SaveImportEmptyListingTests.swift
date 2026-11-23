// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// iOS's SMB client lists a picked share folder as empty however it holds files, though it gives
/// the whole folder as a zip (`NSFileCoordinator` `.forUploading`). A folder that lists empty is
/// read from that zip, unpacked, for every import (library and in-game, every system). Here the
/// folders are local, the enumerator hooked to list nothing; the zip and its unpacking are real.
final class SaveImportEmptyListingTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var paths: SavePaths!
    private var locked: URL?

    override func setUpWithError() throws {
        FolderSnapshot.removeAll()
        root = fm.temporaryDirectory.appendingPathComponent("rp-empty-listing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        paths = SavePaths(documentsURL: root.appendingPathComponent("Documents"))
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws {
        // An unreadable folder made for a test, readable again so it can be removed.
        if let locked { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        FolderWalk.bulkListing = nil
        FolderSnapshot.take = nil
        FolderSnapshot.removeAll()
        try? fm.removeItem(at: root)
    }

    private let atv = LibraryGame(displayName: "ATV Offroad Fury Pro", systemID: .psp, relativePath: "ATV.iso", pspProductID: "UCUS98648")

    /// The enumerator lists nothing in folders with these names, as on the share.
    private func listsNothing(_ names: Set<String>) {
        FolderWalk.bulkListing = { names.contains($0.lastPathComponent) ? [] : nil }
    }

    private var snapshots: [String] { (try? fm.contentsOfDirectory(atPath: FolderSnapshot.root.path)) ?? [] }

    /// Shaped like LittleBigPlanet's profile slot (whose PARAM.SFO names none of its files):
    /// PARAM.SFO, three pictures, a movie and 18 data files, 22 in all, each with its own bytes.
    private func makeSlot(in parent: String = "Share/Game Saves") throws -> (URL, [String: Data]) {
        let slot = root.appendingPathComponent("\(parent)/UCUS98648PROFILE00", isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        var files = ["PARAM.SFO": Data("\0PSF synthetic".utf8)]
        for (index, name) in ["ICON0.PNG", "ICON1.PMF", "PIC1.PNG"].enumerated() {
            files[name] = Data(repeating: UInt8(index + 1), count: 1_000 + index * 500)
        }
        for index in 0..<18 {
            files[String(format: "DATA%02d.BIN", index)] = Data((0..<(4_096 + index * 37)).map { UInt8(($0 + index) & 0xFF) })
        }
        for (name, data) in files { try data.write(to: slot.appendingPathComponent(name)) }
        return (slot, files)
    }

    private func assertHolds(_ folder: URL, _ files: [String: Data], line: UInt = #line) throws {
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path).sorted(), files.keys.sorted(), line: line)
        for (name, data) in files {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(name)), data, name, line: line)
        }
    }

    /// Library "+ → Saves": scan, plan and install, as the app does, then the pick's access ends.
    private func libraryImport(_ pick: URL, games: [LibraryGame]) throws -> SaveImportBatch {
        let access = SecurityScopedAccess([pick])
        defer { access.stop() }
        let batch = LibrarySaveImporter().plan(SaveFolderScanner.scan(access.readURLs), games: games, paths: paths)
        for item in batch.items {
            try LibrarySaveImporter.install(item.plan, from: item.sourceURL, overwrite: false, gameIDs: item.gameIDs, paths: paths)
        }
        XCTAssertFalse(snapshots.isEmpty, "the folder wasn't read from its zipped copy")
        return batch
    }

    // MARK: Read from the zipped copy

    func testTheLibraryImportCopiesAll22FilesOfASlotListedEmpty() throws {
        let (slot, files) = try makeSlot()
        listsNothing(["UCUS98648PROFILE00"])
        let batch = try libraryImport(slot, games: [atv])
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(batch.items.map(\.game.id), [atv.id])
        try assertHolds(paths.pspSavedataDirectory.appendingPathComponent("UCUS98648PROFILE00"), files)
        XCTAssertEqual(files.count, 22)
        XCTAssertEqual(snapshots, [], "the unpacked copy outlived the import")
    }

    func testTheInGameImportCopiesAll22FilesOfASlotListedEmpty() throws {
        let (slot, files) = try makeSlot()
        listsNothing(["UCUS98648PROFILE00"])
        let access = SecurityScopedAccess([slot])
        let plan = try SaveGameImporter().planImport(from: slot, for: atv, paths: paths, fileManager: fm)
        try LibrarySaveImporter.install(plan, from: slot, overwrite: false, gameIDs: [atv.id], paths: paths)
        XCTAssertFalse(snapshots.isEmpty, "the folder wasn't read from its zipped copy")
        access.stop()
        try assertHolds(plan.destinationURL, files)
        XCTAssertEqual(snapshots, [])
    }

    /// Every folder down to the slot lists empty; each is read from its zipped copy.
    func testAFolderAboveTheSlotFindsItWhenEveryFolderListsEmpty() throws {
        let (_, files) = try makeSlot(in: "Pick/PSP/SAVEDATA")
        listsNothing(["Pick", "PSP", "SAVEDATA", "UCUS98648PROFILE00"])
        let batch = try libraryImport(root.appendingPathComponent("Pick", isDirectory: true), games: [atv])
        XCTAssertEqual(batch.items.map(\.game.id), [atv.id], "\(batch.skipped) \(batch.notes)")
        try assertHolds(paths.pspSavedataDirectory.appendingPathComponent("UCUS98648PROFILE00"), files)
    }

    /// Other systems' saves, in nested folders with spaces (and an accent) in their names.
    func testNestedSavesWithSpacesInAFolderListedEmptyImport() throws {
        let emerald = LibraryGame(displayName: "Pokémon Emerald", systemID: .gba, relativePath: "Pokémon Emerald (USA).gba")
        let mario = LibraryGame(displayName: "Super Mario World", systemID: .snes, relativePath: "Super Mario World (USA).sfc")
        let saves = root.appendingPathComponent("Share/My Saves", isDirectory: true)
        let emeraldSave = Data((0..<131_072).map { UInt8($0 % 251) })
        let marioSave = Data((0..<2_048).map { UInt8($0 % 13) })
        for (path, data) in [("Game Boy Advance/Pokémon Emerald (USA).sav", emeraldSave),
                             ("Super Nintendo/Old ones/Super Mario World (USA).srm", marioSave)] {
            let url = saves.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        listsNothing(["My Saves"])
        let batch = try libraryImport(saves, games: [emerald, mario])
        XCTAssertEqual(batch.skipped, [])
        XCTAssertEqual(Set(batch.items.map(\.game.id)), [emerald.id, mario.id])
        XCTAssertEqual(try Data(contentsOf: paths.sramURL(forRelativeROMPath: emerald.relativePath)), emeraldSave)
        XCTAssertEqual(try Data(contentsOf: paths.sramURL(forRelativeROMPath: mario.relativePath)), marioSave)
    }

    func testAnEmptyFolderIsJustEmptyAndLeavesNoCopy() throws {
        let empty = root.appendingPathComponent("Pick/Empty", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        let found = LibrarySaveImporter().plan(SaveFolderScanner.scan([empty]), games: [atv], paths: paths)
        XCTAssertEqual(found.items, [])
        XCTAssertEqual(found.skipped, [])
        XCTAssertEqual(snapshots, [])
    }

    func testACancelledImportLeavesNoCopy() throws {
        let (slot, _) = try makeSlot()
        listsNothing(["UCUS98648PROFILE00"])
        let cancellation = ImportCancellation()
        cancellation.cancel()
        XCTAssertThrowsError(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: fm, cancellation: cancellation)) {
            XCTAssertTrue($0 is CancellationError, "\($0)")
        }
        XCTAssertEqual(snapshots, [])
    }

    // MARK: No zipped copy: the one fallback

    func testWithoutAZippedCopyItSaysToCopyTheFolderFirst() throws {
        let (slot, _) = try makeSlot()
        listsNothing(["UCUS98648PROFILE00"])
        FolderSnapshot.take = { _ in throw CocoaError(.fileReadUnknown) }
        let message = "iOS listed “UCUS98648PROFILE00” as empty and couldn't give RetroPlay a copy of it. Copy the folder to On My iPhone in Files and import it from there."
        XCTAssertThrowsError(try SaveGameImporter().planImport(from: slot, for: atv, paths: paths, fileManager: fm)) {
            XCTAssertEqual($0 as? SaveGameImportError, .listedEmpty("UCUS98648PROFILE00"))
            XCTAssertEqual($0.localizedDescription, message)
        }
        let found = LibrarySaveImporter().plan(SaveFolderScanner.scan([slot]), games: [atv], paths: paths)
        XCTAssertEqual(found.items, [])
        XCTAssertEqual(found.skipped.map(\.reason), [message])
    }

    /// A folder the file system won't list is a read error, not a folder listed empty.
    func testAFolderThatCantBeListedIsAnError() throws {
        let (slot, _) = try makeSlot()
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: slot.path)
        locked = slot
        XCTAssertThrowsError(try SaveGameImporter.validatePSPFolderContents(slot, fileManager: fm)) {
            XCTAssertTrue($0.localizedDescription.contains("couldn't be read"), $0.localizedDescription)
        }
    }

    // MARK: Spelling

    /// A device's picks and listings mix /var/… and /private/var/… (/var is a link): the
    /// walk goes by what each listing returns, so either spelling finds the slot.
    func testAPickSpelledThroughTheVarLinkOrItsTargetFindsTheSlot() throws {
        _ = try makeSlot(in: "Pick/PSP/SAVEDATA")
        let path = root.appendingPathComponent("Pick", isDirectory: true).path
        // Only where the temporary folder sits under the /var link (macOS, a device); the
        // Simulator keeps it under the Mac user's folder.
        guard path.hasPrefix("/private/var/") || path.hasPrefix("/var/") else {
            throw XCTSkip("the temporary folder isn't under the /var link here: \(path)")
        }
        let short = path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
        for spelling in [short, "/private" + short] {
            let found = LibrarySaveImporter().plan(SaveFolderScanner.scan([URL(fileURLWithPath: spelling, isDirectory: true)]), games: [atv], paths: paths)
            XCTAssertEqual(found.items.map(\.game.id), [atv.id], "\(spelling): \(found.skipped)")
        }
    }
}

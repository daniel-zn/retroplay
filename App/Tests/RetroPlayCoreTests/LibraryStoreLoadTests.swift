// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

@MainActor
final class LibraryStoreLoadTests: XCTestCase {
    func testCorruptLibraryJSONSurfacesLoadFailure() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-load-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("{ not valid json".utf8).write(to: root.appendingPathComponent("library.json"))

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)

        XCTAssertTrue(store.games.isEmpty)
        XCTAssertNotNil(store.libraryLoadFailureMessage)
    }

    func testMissingLibraryClearsLoadFailure() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-load-missing-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)

        XCTAssertTrue(store.games.isEmpty)
        XCTAssertNil(store.libraryLoadFailureMessage)
    }

    func testValidLibraryLoadsWithoutFailure() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-load-valid-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let inbox = root.appendingPathComponent("inbox.gba")
        try Data("not-a-copyrighted-rom".utf8).write(to: inbox)

        let importer = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        _ = try importer.importFiles(from: [inbox])
        XCTAssertEqual(importer.games.count, 1)
        XCTAssertNil(importer.libraryLoadFailureMessage)

        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertEqual(reloaded.games.count, 1)
        XCTAssertNil(reloaded.libraryLoadFailureMessage)
    }

    func testPartialImportRollbackRemovesStagedROM() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-import-rollback-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let inbox = root.appendingPathComponent("rollback.gba")
        try Data("not-a-copyrighted-rom".utf8).write(to: inbox)
        try fm.createDirectory(at: root.appendingPathComponent("library.json"), withIntermediateDirectories: true)

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: root)
        XCTAssertThrowsError(try store.importFiles(from: [inbox]))
        XCTAssertTrue(store.games.isEmpty)
        let staged = store.gamesDirectoryURL.appendingPathComponent("rollback.gba")
        XCTAssertFalse(fm.fileExists(atPath: staged.path))
    }

    // MARK: - Legacy display names

    private func writeLibrary(_ games: [LibraryGame], documents: URL, support: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try encoder.encode(games).write(to: support.appendingPathComponent("library.json"))
    }

    private let fm = FileManager.default

    func testLoadCleansRawFileDerivedNamesAndKeepsCustomNames() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("rp-names-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)

        let raw = LibraryGame(
            displayName: "Legend of Zelda, The (USA)",
            systemID: .gba,
            relativePath: "Legend of Zelda, The (USA).gba"
        )
        let collided = LibraryGame(
            displayName: "Mario Kart DS (USA) (En,Fr,Es)",
            systemID: .nds,
            relativePath: "Mario Kart DS (USA) (En,Fr,Es)-1.nds"
        )
        let pspCode = LibraryGame(
            displayName: "ULUS10238 Game Name",
            systemID: .psp,
            relativePath: "ULUS10238 Game Name.iso"
        )
        let custom = LibraryGame(
            displayName: "My Zelda (USA)",
            systemID: .gba,
            relativePath: "Zelda (USA).gba"
        )
        let alreadyClean = LibraryGame(displayName: "Tetris", systemID: .gba, relativePath: "Tetris.gba")
        try writeLibrary([raw, collided, pspCode, custom, alreadyClean], documents: documents, support: support)

        let store = LibraryStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)
        let names = Dictionary(uniqueKeysWithValues: store.games.map { ($0.id, $0.displayName) })
        XCTAssertEqual(names[raw.id], "The Legend of Zelda")
        XCTAssertEqual(names[collided.id], "Mario Kart DS")
        XCTAssertEqual(names[pspCode.id], "Game Name")
        XCTAssertEqual(names[custom.id], "My Zelda (USA)")
        XCTAssertEqual(names[alreadyClean.id], "Tetris")

        // Persisted: a fresh store reads the cleaned names back from disk.
        let reloaded = LibraryStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)
        XCTAssertEqual(reloaded.games.first { $0.id == raw.id }?.displayName, "The Legend of Zelda")
        XCTAssertEqual(reloaded.games.first { $0.id == custom.id }?.displayName, "My Zelda (USA)")
    }

    func testLegacyNameCleanupIsIdempotent() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("rp-names-idem-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)

        let raw = LibraryGame(displayName: "Metroid (USA) [!]", systemID: .gba, relativePath: "Metroid (USA) [!].gba")
        try writeLibrary([raw], documents: documents, support: support)

        let first = LibraryStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)
        XCTAssertEqual(first.games.map(\.displayName), ["Metroid"])
        let afterFirst = try Data(contentsOf: first.libraryFileURL)

        let second = LibraryStore(fileManager: fm, documentsDirectoryURL: documents, supportDirectoryURL: support)
        XCTAssertEqual(second.games.map(\.displayName), ["Metroid"])
        XCTAssertEqual(try Data(contentsOf: second.libraryFileURL), afterFirst)

        var games = second.games
        XCTAssertFalse(LibraryStore.cleanLegacyDisplayNames(&games))
        XCTAssertEqual(games, second.games)
    }

    func testLegacyNameCleanupMatchesImportNaming() {
        // A clean import name after a base-name clash is left as is.
        let clash = LibraryGame(displayName: "Game", systemID: .nds, relativePath: "Game-1.nds")
        XCTAssertNil(LibraryStore.cleanedLegacyDisplayName(for: clash))
        // A title that really ends in "-2" keeps its digits.
        let dashed = LibraryGame(displayName: "Game-2 (USA)", systemID: .nds, relativePath: "Game-2 (USA).nds")
        XCTAssertEqual(LibraryStore.cleanedLegacyDisplayName(for: dashed), "Game-2")
        // Not the stored base with or without the uniqueness suffix: the user's own name.
        let renamed = LibraryGame(displayName: "Game (USA)-1", systemID: .nds, relativePath: "Game (USA)-2.nds")
        XCTAssertNil(LibraryStore.cleanedLegacyDisplayName(for: renamed))
    }
}

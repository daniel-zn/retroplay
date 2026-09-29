// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class PSPProductIDTests: XCTestCase {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-psp-id-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - PARAM.SFO / normalization

    func testParamSFOParsesDiscID() {
        let sfo = Self.makeParamSFO(discID: "ULUS-12345")
        XCTAssertEqual(PSPParamSFO.discID(from: sfo), "ULUS12345")
    }

    func testProductIDNormalizerUppercasesAndStripsHyphen() {
        XCTAssertEqual(PSPProductIDNormalizer.normalize("ulus-12345"), "ULUS12345")
        XCTAssertEqual(PSPProductIDNormalizer.normalize("  ULUS12345  "), "ULUS12345")
        XCTAssertNil(PSPProductIDNormalizer.normalize("not-a-valid-id"))
    }

    func testLibraryGameDecodesWithoutPSPProductIDField() throws {
        let json = """
        [
          {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "displayName": "Legacy PSP",
            "systemID": "psp",
            "relativePath": "Game.iso",
            "dateAdded": "2024-01-01T00:00:00Z"
          }
        ]
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let games = try decoder.decode([LibraryGame].self, from: json)
        XCTAssertEqual(games.count, 1)
        XCTAssertNil(games[0].pspProductID)
    }

    func testLibraryGameEncodesNormalizedPSPProductID() throws {
        let game = LibraryGame(
            displayName: "Test",
            systemID: .psp,
            relativePath: "Game.iso",
            pspProductID: "ulus-12345"
        )
        XCTAssertEqual(game.pspProductID, "ULUS12345")

        let data = try JSONEncoder().encode([game])
        let decoded = try JSONDecoder().decode([LibraryGame].self, from: data)
        XCTAssertEqual(decoded[0].pspProductID, "ULUS12345")
    }

    // MARK: - PBP extraction

    func testPBPExtractorReadsEmbeddedProductID() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pbpURL = root.appendingPathComponent("Game.pbp")
        let sfo = Self.makeParamSFO(discID: "ULUS-99999")
        try Self.makePBP(containing: sfo).write(to: pbpURL)

        switch PSPProductIDExtractor.extract(from: pbpURL) {
        case .found(let id):
            XCTAssertEqual(id, "ULUS99999")
        default:
            XCTFail("expected found product ID")
        }
    }

    func testCSOReportsUnsupportedFormat() {
        let url = URL(fileURLWithPath: "/tmp/example.cso")
        guard case .unsupportedFormat(let reason) = PSPProductIDExtractor.extract(from: url) else {
            return XCTFail("expected unsupportedFormat")
        }
        XCTAssertTrue(reason.contains("cso"))
    }

    // MARK: - ROM ownership validation

    func testROMOwnershipRejectsTitleMismatch() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pbpURL = root.appendingPathComponent("Other.pbp")
        let sfo = Self.makeParamSFO(discID: "ULUS-11111")
        try Self.makePBP(containing: sfo).write(to: pbpURL)

        let game = LibraryGame(
            displayName: "Mine",
            systemID: .psp,
            relativePath: "Mine.pbp",
            pspProductID: "ULUS99999"
        )

        XCTAssertThrowsError(try PSPROMOwnership.validate(romURL: pbpURL, game: game)) { error in
            guard case .romLoadFailed(let message) = error as? EmulatorCoreError else {
                return XCTFail("expected romLoadFailed")
            }
            XCTAssertTrue(message.contains("ULUS11111"))
            XCTAssertTrue(message.contains("ULUS99999"))
        }
    }

    // MARK: - Save import matching

    func testPSPImportRejectsTitleMismatch() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("ULUS11111", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.makeParamSFO(discID: "ULUS-11111").write(to: folder.appendingPathComponent("PARAM.SFO"))

        let game = LibraryGame(
            displayName: "Game",
            systemID: .psp,
            relativePath: "Game.iso",
            pspProductID: "ULUS99999"
        )
        let importer = SaveGameImporter()

        XCTAssertThrowsError(try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)) { error in
            XCTAssertEqual(
                error as? SaveGameImportError,
                .pspTitleMismatch(expected: "ULUS99999", imported: "ULUS11111")
            )
        }
    }

    func testPSPImportAllowsMatchWhenProductIDKnown() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let folder = root.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.makeParamSFO(discID: "ULUS-12345").write(to: folder.appendingPathComponent("PARAM.SFO"))

        let game = LibraryGame(
            displayName: "Game",
            systemID: .psp,
            relativePath: "Game.iso",
            pspProductID: "ULUS12345"
        )
        let importer = SaveGameImporter()
        let plan = try importer.planImport(from: folder, for: game, paths: paths, fileManager: fm)
        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/SAVEDATA/ULUS12345"))
    }

    // MARK: - Cleanup ownership

    func testCleanupDeletesOnlyExactSavedataFolder() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let mine = paths.pspSavedataDirectory.appendingPathComponent("ULUS11111", isDirectory: true)
        let other = paths.pspSavedataDirectory.appendingPathComponent("ULUS22222", isDirectory: true)
        try fm.createDirectory(at: mine, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: mine.appendingPathComponent("PARAM.SFO"))
        try Data("other".utf8).write(to: other.appendingPathComponent("PARAM.SFO"))

        let rom = paths.gameROMURL(forRelativePath: "Game.iso")
        try fm.createDirectory(at: rom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("iso".utf8).write(to: rom)

        let game = LibraryGame(
            displayName: "Game",
            systemID: .psp,
            relativePath: "Game.iso",
            pspProductID: "ULUS11111"
        )
        let result = try GameArtifactCleanup.removeArtifacts(for: game, paths: paths, fileManager: fm)

        XCTAssertEqual(result, .complete)
        XCTAssertFalse(fm.fileExists(atPath: mine.path))
        XCTAssertTrue(fm.fileExists(atPath: other.path))
    }

    func testCleanupRetainsSavedataWhenProductIDUnknown() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let savedata = paths.pspSavedataDirectory.appendingPathComponent("ULUS12345", isDirectory: true)
        try fm.createDirectory(at: savedata, withIntermediateDirectories: true)
        try Data("save".utf8).write(to: savedata.appendingPathComponent("PARAM.SFO"))

        let rom = paths.gameROMURL(forRelativePath: "Game.iso")
        try fm.createDirectory(at: rom.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("iso".utf8).write(to: rom)

        let game = LibraryGame(displayName: "Game", systemID: .psp, relativePath: "Game.iso")
        let result = try GameArtifactCleanup.removeArtifacts(for: game, paths: paths, fileManager: fm)

        XCTAssertTrue(result.retainedPSPSavedata)
        XCTAssertNotNil(result.retainedPSPSavedataReason)
        XCTAssertTrue(fm.fileExists(atPath: savedata.path))
    }

    // MARK: - Inventory helper

    func testSavedataInventoryMapsOwnership() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)

        let owned = paths.pspSavedataDirectory.appendingPathComponent("ULUS11111", isDirectory: true)
        let orphan = paths.pspSavedataDirectory.appendingPathComponent("ULUS99999", isDirectory: true)
        try fm.createDirectory(at: owned, withIntermediateDirectories: true)
        try fm.createDirectory(at: orphan, withIntermediateDirectories: true)

        let known = LibraryGame(
            displayName: "Known",
            systemID: .psp,
            relativePath: "Known.iso",
            pspProductID: "ULUS11111"
        )
        let missing = LibraryGame(
            displayName: "Missing",
            systemID: .psp,
            relativePath: "Missing.iso",
            pspProductID: "ULUS22222"
        )

        let inventory = try PSPSavedataInventory.scan(games: [known, missing], paths: paths, fileManager: fm)
        XCTAssertEqual(inventory.slots.map(\.productID), ["ULUS11111", "ULUS99999"])
        XCTAssertEqual(inventory.unownedProductIDs, ["ULUS99999"])
        XCTAssertEqual(inventory.gamesMissingSavedata, [missing.id])
    }

    func testSavedataInventoryListsSuffixedFoldersForOwningGame() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        for name in ["ULUS10041DATA00", "ULUS10041DATA01", "ULES00151SAVE", "SAVEDATA"] {
            try fm.createDirectory(
                at: paths.pspSavedataDirectory.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let game = LibraryGame(
            displayName: "Owner",
            systemID: .psp,
            relativePath: "Owner.iso",
            pspProductID: "ULUS10041"
        )
        let other = LibraryGame(
            displayName: "Other",
            systemID: .psp,
            relativePath: "Other.iso",
            pspProductID: "ULUS10042"
        )

        let inventory = try PSPSavedataInventory.scan(games: [game, other], paths: paths, fileManager: fm)
        XCTAssertEqual(
            inventory.slots.map(\.folderName),
            ["ULES00151SAVE", "ULUS10041DATA00", "ULUS10041DATA01"]
        )
        XCTAssertEqual(inventory.slots.map(\.productID), ["ULES00151", "ULUS10041", "ULUS10041"])
        XCTAssertEqual(inventory.unownedProductIDs, ["ULES00151SAVE"])
        XCTAssertEqual(inventory.gamesMissingSavedata, [other.id])
    }

    // MARK: - Fixtures

    private static func makeParamSFO(discID: String) -> Data {
        let key = Data("DISC_ID\0".utf8)
        let value = Data((discID + "\0").utf8)
        let indexCount = 1
        let headerSize = 20
        let indexTableSize = indexCount * 16
        let keyTableOffset = headerSize + indexTableSize
        let dataTableOffset = keyTableOffset + key.count
        let dataOffset = 0

        var data = Data()
        data.append(u32LE(0x46535000)) // \0PSF
        data.append(u32LE(0x00000101))
        data.append(u32LE(UInt32(keyTableOffset)))
        data.append(u32LE(UInt32(dataTableOffset)))
        data.append(u32LE(UInt32(indexCount)))

        data.append(u16LE(0)) // key offset
        data.append(u16LE(4)) // utf-8-s
        data.append(u32LE(UInt32(value.count)))
        data.append(u32LE(UInt32(value.count)))
        data.append(u32LE(UInt32(dataOffset)))

        data.append(key)
        data.append(value)
        return data
    }

    private static func makePBP(containing sfo: Data) -> Data {
        let headerSize = 40
        let sfoOffset = headerSize
        let icon0Offset = sfoOffset + sfo.count

        var pbp = Data()
        pbp.append(Data([0x00, 0x50, 0x42, 0x50])) // \0PBP
        pbp.append(u32LE(0x00000100)) // version
        pbp.append(u32LE(UInt32(sfoOffset))) // PARAM.SFO start
        pbp.append(u32LE(UInt32(icon0Offset))) // ICON0 / end of PARAM.SFO
        for _ in 0..<6 {
            pbp.append(u32LE(UInt32(icon0Offset)))
        }
        pbp.append(sfo)
        return pbp
    }

    private static func u16LE(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    private static func u32LE(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Compression
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

    /// A CSO (an ISO in deflated 2 KB blocks, one block stored as is, as CSO tools leave a
    /// block that doesn't shrink) gives its PARAM.SFO's ID as the ISO does.
    func testCSOExtractorReadsEmbeddedProductID() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let iso = Self.makeISO(sfo: Self.makeParamSFO(discID: "UCUS-98744"))
        let isoURL = root.appendingPathComponent("Game.iso")
        try iso.write(to: isoURL)
        XCTAssertEqual(PSPProductIDExtractor.extract(from: isoURL), .found("UCUS98744"))
        for align: UInt8 in [0, 2] {
            let csoURL = root.appendingPathComponent("Game-\(align).cso")
            try Self.makeCSO(iso, align: align, storedBlocks: [21]).write(to: csoURL)
            XCTAssertEqual(PSPProductIDExtractor.extract(from: csoURL), .found("UCUS98744"), "align \(align)")
        }
    }

    func testCHDReportsUnsupportedFormat() {
        let url = URL(fileURLWithPath: "/tmp/example.chd")
        guard case .unsupportedFormat(let reason) = PSPProductIDExtractor.extract(from: url) else {
            return XCTFail("expected unsupportedFormat")
        }
        XCTAssertTrue(reason.contains("chd"))
    }

    /// A save picked for a game whose ID can't be read is still placed, with a warning that it
    /// couldn't be checked against the game, never as a plain "Imported".
    func testPSPImportForGameWithUnknownIDWarnsItWasNotChecked() throws {
        let fm = FileManager.default
        let root = tempRoot()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        try paths.ensureDirectories(fileManager: fm)
        let folder = try Self.makeSavedataFolder(named: "UCES01264SAVE00", in: root)

        let game = LibraryGame(displayName: "Game", systemID: .psp, relativePath: "Game.chd")
        let plan = try SaveGameImporter().planImport(from: folder, for: game, paths: paths, fileManager: fm)
        XCTAssertTrue(plan.destinationURL.path.hasSuffix("/psp-memstick/PSP/SAVEDATA/UCES01264SAVE00"))
        let warning = try XCTUnwrap(plan.warning)
        XCTAssertTrue(warning.contains("UCES01264SAVE00") && warning.contains("couldn't check"), warning)
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

    /// A save slot as a PSP writes it: PARAM.SFO (listing DATA.BIN), DATA.BIN and ICON0.PNG.
    static func makeSavedataFolder(named name: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent("picked", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try makeParamSFO(discID: String(name.prefix(9))).write(to: folder.appendingPathComponent("PARAM.SFO"))
        try Data(repeating: 0xA5, count: 64 * 1024).write(to: folder.appendingPathComponent("DATA.BIN"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("ICON0.PNG"))
        return folder
    }

    /// PVD → root (sector 20) → PSP_GAME (sector 21) → PARAM.SFO (sector 22), padded to 32 sectors.
    static func makeISO(sfo: Data) -> Data {
        let sector = 2048
        var iso = Data(repeating: 0, count: sector * 32)
        let pvd = 16 * sector
        iso[pvd] = 1
        iso.replaceSubrange((pvd + 1)..<(pvd + 6), with: Data("CD001".utf8))
        iso.replaceSubrange((pvd + 156 + 2)..<(pvd + 156 + 6), with: u32LE(20))
        iso.replaceSubrange((pvd + 156 + 10)..<(pvd + 156 + 14), with: u32LE(UInt32(sector)))
        let pspGame = directoryRecord(name: "PSP_GAME", lba: 21, size: UInt32(sector), isDir: true)
        iso.replaceSubrange((20 * sector)..<(20 * sector + pspGame.count), with: pspGame)
        let param = directoryRecord(name: "PARAM.SFO;1", lba: 22, size: UInt32(sfo.count), isDir: false)
        iso.replaceSubrange((21 * sector)..<(21 * sector + param.count), with: param)
        iso.replaceSubrange((22 * sector)..<(22 * sector + sfo.count), with: sfo)
        return iso
    }

    private static func directoryRecord(name: String, lba: UInt32, size: UInt32, isDir: Bool) -> Data {
        let nameBytes = Data(name.utf8)
        var rec = Data(repeating: 0, count: 33)
        rec.replaceSubrange(2..<6, with: u32LE(lba))
        rec.replaceSubrange(10..<14, with: u32LE(size))
        rec[25] = isDir ? 0x02 : 0x00
        rec[32] = UInt8(nameBytes.count)
        rec.append(nameBytes)
        if rec.count % 2 == 1 { rec.append(0) }
        rec[0] = UInt8(rec.count)
        return rec
    }

    /// CISO v1: a 24-byte header, an index of block offsets (shifted right by `align`; the top
    /// bit marks a block stored as is), then each block raw-deflated, padded to the alignment.
    static func makeCSO(_ iso: Data, align: UInt8, storedBlocks: Set<Int>) -> Data {
        let block = 2048
        let blocks = iso.count / block
        var body = Data()
        var index: [UInt32] = []
        let headerAndIndex = 24 + (blocks + 1) * 4
        func pad() {
            let unit = 1 << Int(align)
            while (headerAndIndex + body.count) % unit != 0 { body.append(0) }
        }
        for b in 0..<blocks {
            pad()
            let offset = UInt32((headerAndIndex + body.count) >> Int(align))
            let raw = iso.subdata(in: (b * block)..<((b + 1) * block))
            if storedBlocks.contains(b) {
                index.append(offset | 0x8000_0000)
                body.append(raw)
            } else {
                index.append(offset)
                var out = [UInt8](repeating: 0, count: block * 2)
                let n = raw.withUnsafeBytes { src in
                    compression_encode_buffer(&out, out.count, src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
                }
                body.append(contentsOf: out.prefix(n))
            }
        }
        pad()
        index.append(UInt32((headerAndIndex + body.count) >> Int(align)))
        var cso = Data("CISO".utf8)
        cso.append(u32LE(24))
        cso.append(u32LE(UInt32(iso.count)))
        cso.append(u32LE(0))
        cso.append(u32LE(UInt32(block)))
        cso.append(contentsOf: [1, align, 0, 0])
        for entry in index { cso.append(u32LE(entry)) }
        cso.append(body)
        return cso
    }

    static func makeParamSFO(discID: String) -> Data {
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

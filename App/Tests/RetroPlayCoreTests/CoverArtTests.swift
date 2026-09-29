// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import XCTest
@testable import RetroPlayCore

final class CoverArtTests: XCTestCase {
    func testGBAAndN64HaveNoEmbeddedCover() throws {
        let url = try writeTemp("empty.gba", Data("FAKEGBA".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(CoverArtExtractor.extractImageData(from: url, system: .gba))
        let n64 = try writeTemp("empty.z64", Data("FAKEN64".utf8))
        XCTAssertNil(CoverArtExtractor.extractImageData(from: n64, system: .n64))
    }

    func testCSOIsSkippedWithoutNetwork() throws {
        var cso = Data("CISO".utf8)
        cso.append(Data(repeating: 0, count: 64))
        let url = try writeTemp("game.cso", cso)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(CoverArtExtractor.extractImageData(from: url, system: .psp))
    }

    func testPBPIcon0IsExtractedLocally() throws {
        let png = try XCTUnwrap(CoverArtPNG.encodeRGBA(
            width: 2,
            height: 2,
            pixels: [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 0, 255
            ]
        ))
        let pbp = makePBP(icon0: png)
        let url = try writeTemp("game.pbp", pbp)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let extracted = try XCTUnwrap(CoverArtExtractor.extractImageData(from: url, system: .psp))
        XCTAssertTrue(extracted.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testISO9660Icon0IsExtractedLocally() throws {
        let png = try XCTUnwrap(CoverArtPNG.encodeRGBA(
            width: 2,
            height: 2,
            pixels: Array(repeating: 180, count: 16)
        ))
        let iso = makeISO(withPNGNamed: "ICON0.PNG", png: png)
        let url = try writeTemp("game.iso", iso)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let extracted = try XCTUnwrap(CoverArtExtractor.extractImageData(from: url, system: .psp))
        XCTAssertEqual(extracted, png)
    }

    func testNDSBannerBecomesPNG() throws {
        var rom = Data(repeating: 0, count: 0x800)
        // Banner at 0x200
        rom[0x68] = 0x00
        rom[0x69] = 0x02
        rom[0x6A] = 0x00
        rom[0x6B] = 0x00
        let banner = 0x200
        rom[banner + 0x20] = 0x11
        // Palette index 1 = white (RGB555 0x7FFF)
        rom[banner + 0x220 + 2] = 0xFF
        rom[banner + 0x220 + 3] = 0x7F
        let url = try writeTemp("game.nds", rom)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let extracted = try XCTUnwrap(CoverArtExtractor.extractImageData(from: url, system: .nds))
        XCTAssertTrue(extracted.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testROMCoverIsInstalledWithROMOrigin() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-cover-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = CoverArtStore(fileManager: fm, documentsDirectoryURL: root)
        let id = UUID()
        let png = try XCTUnwrap(CoverArtPNG.encodeRGBA(
            width: 2,
            height: 2,
            pixels: Array(repeating: 40, count: 16)
        ))
        let pbp = makePBP(icon0: png)
        let romURL = root.appendingPathComponent("game.pbp")
        try pbp.write(to: romURL)
        XCTAssertTrue(try store.installFromGameFile(gameID: id, fileURL: romURL, system: .psp))
        XCTAssertEqual(store.origin(forGameID: id), .rom)
        XCTAssertTrue(store.hasCover(forGameID: id))
        XCTAssertEqual(store.displayableCoverURL(forGameID: id), store.coverURL(forGameID: id))
    }

    func testLegacyCoverWithoutOriginIsNotMisclassifiedAsScreenshot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-cover-legacy-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = CoverArtStore(fileManager: fm, documentsDirectoryURL: root)
        let id = UUID()
        try store.ensureDirectory()
        try Data("legacy-user-cover".utf8).write(to: store.coverURL(forGameID: id))
        XCTAssertTrue(store.hasCover(forGameID: id))
        XCTAssertNil(store.origin(forGameID: id))
        XCTAssertEqual(store.displayableCoverURL(forGameID: id), store.coverURL(forGameID: id))
        try store.removeCover(forGameID: id)
        XCTAssertFalse(store.hasCover(forGameID: id))
    }

    func testScreenshotOriginCoverIsIgnoredButRemainsRemovable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-cover-frame-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = CoverArtStore(fileManager: fm, documentsDirectoryURL: root)
        let id = UUID()
        try store.ensureDirectory()
        try Data("old-frame-cover".utf8).write(to: store.coverURL(forGameID: id))
        try "frame".write(to: store.originURL(forGameID: id), atomically: true, encoding: .utf8)

        XCTAssertTrue(store.hasCover(forGameID: id))
        XCTAssertEqual(store.origin(forGameID: id), .frame)
        XCTAssertNil(store.displayableCoverURL(forGameID: id))
        try store.removeCover(forGameID: id)
        XCTAssertFalse(store.hasCover(forGameID: id))
    }

    private func writeTemp(_ name: String, _ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rp-art-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func makePBP(icon0: Data) -> Data {
        var data = Data()
        data.append(contentsOf: [0x00, 0x50, 0x42, 0x50])
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00])
        let header = 8 + 8 * 4
        let icon0Off = UInt32(header)
        let icon1Off = UInt32(header + icon0.count)
        for offset in [UInt32(header), icon0Off, icon1Off, icon1Off, icon1Off, icon1Off, icon1Off, icon1Off] {
            var le = offset.littleEndian
            data.append(Data(bytes: &le, count: 4))
        }
        data.append(icon0)
        return data
    }

    private func makeISO(withPNGNamed name: String, png: Data) -> Data {
        let sector = 2048
        var iso = Data(repeating: 0, count: sector * 24)
        // PVD at sector 16
        let pvd = 16 * sector
        iso[pvd] = 1
        iso.replaceSubrange((pvd + 1)..<(pvd + 6), with: Data("CD001".utf8))
        let fileLBA: UInt32 = 22
        let rec = isoDirectoryRecord(name: name, lba: fileLBA, size: UInt32(png.count), isDir: false)
        // Root directory record at offset 156 of PVD; point at sector 20.
        var root = isoDirectoryRecord(name: "\0", lba: 20, size: UInt32(rec.count + 40), isDir: true)
        while root.count < 34 { root.append(0) }
        iso.replaceSubrange((pvd + 156)..<(pvd + 156 + min(34, root.count)), with: root.prefix(34))
        iso.replaceSubrange((pvd + 158)..<(pvd + 162), with: u32LE(20))
        iso.replaceSubrange((pvd + 166)..<(pvd + 170), with: u32LE(UInt32(rec.count + 40)))

        let dirOff = 20 * sector
        iso.replaceSubrange(dirOff..<(dirOff + rec.count), with: rec)
        let fileOff = Int(fileLBA) * sector
        iso.replaceSubrange(fileOff..<(fileOff + png.count), with: png)
        return iso
    }

    private func isoDirectoryRecord(name: String, lba: UInt32, size: UInt32, isDir: Bool) -> Data {
        var nameBytes = Data(name.utf8)
        if !isDir, !name.contains(";") {
            nameBytes.append(contentsOf: ";1".utf8)
        }
        if name == "\0" { nameBytes = Data([0]) }
        var rec = Data(repeating: 0, count: 33)
        rec.replaceSubrange(2..<6, with: u32LE(lba))
        rec.replaceSubrange(10..<14, with: u32LE(size))
        rec[25] = isDir ? 0x02 : 0x00
        rec[32] = UInt8(nameBytes.count)
        rec.append(nameBytes)
        rec[0] = UInt8(rec.count)
        if rec.count % 2 == 1 { rec.append(0) }
        rec[0] = UInt8(rec.count)
        return rec
    }

    private func u32LE(_ value: UInt32) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: 4)
    }

}

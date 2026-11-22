// SPDX-License-Identifier: GPL-3.0-or-later
import Compression
import Foundation

public enum PSPProductIDExtraction: Sendable, Equatable {
    case found(String)
    case notFound
    case unsupportedFormat(String)
}

/// Reads the PSP product/title ID embedded in ISO / CSO / PBP metadata. Never guesses from filenames.
public enum PSPProductIDExtractor: Sendable {
    public static func extract(from fileURL: URL) -> PSPProductIDExtraction {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "iso", "cso":
            return extractFromISO(at: fileURL)
        case "pbp":
            return extractFromPBP(at: fileURL)
        case "chd":
            return .unsupportedFormat(
                ".chd images compress the disc in large hunks RetroPlay doesn't read; their PARAM.SFO stays unread."
            )
        case "prx", "elf":
            return .unsupportedFormat(
                ".\(ext) homebrew binaries do not embed a retail PARAM.SFO product ID."
            )
        default:
            return .unsupportedFormat(".\(ext) is not a supported PSP container for product-ID extraction.")
        }
    }

    // MARK: - PBP

    private static func extractFromPBP(at url: URL) -> PSPProductIDExtraction {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .notFound }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 40), header.count == 40 else { return .notFound }
        guard header.prefix(4) == Data([0x00, 0x50, 0x42, 0x50]) else { return .notFound }

        let sfoOffset = Int(header.u32LE(at: 8))
        let icon0Offset = Int(header.u32LE(at: 12))
        guard sfoOffset > 0, icon0Offset > sfoOffset else { return .notFound }
        let sfoSize = icon0Offset - sfoOffset
        guard sfoSize > 20, sfoSize < 1_000_000 else { return .notFound }

        do {
            try handle.seek(toOffset: UInt64(sfoOffset))
            guard let sfo = try handle.read(upToCount: sfoSize), sfo.count == sfoSize else { return .notFound }
            guard let id = PSPParamSFO.discID(from: sfo) else { return .notFound }
            return .found(id)
        } catch {
            return .notFound
        }
    }

    // MARK: - ISO9660 (plain, or in a CSO's compressed blocks)

    private static func extractFromISO(at url: URL) -> PSPProductIDExtraction {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .notFound }
        defer { try? handle.close() }
        guard let image = DiscImage(handle: handle),
              let sfo = readISOFile(named: "PARAM.SFO", from: image),
              let id = PSPParamSFO.discID(from: sfo)
        else { return .notFound }
        return .found(id)
    }

    private static func readISOFile(named wanted: String, from image: DiscImage) -> Data? {
        let sector = 2048
        guard let pvd = image.read(at: UInt64(16 * sector), count: sector), pvd.count >= 190,
              pvd.prefix(6) == Data([1, 0x43, 0x44, 0x30, 0x30, 0x31])
        else { return nil }
        let root = pvd.subdata(in: (pvd.startIndex + 156)..<(pvd.startIndex + 190))
        let lba = root.u32LE(at: 2)
        let size = Int(root.u32LE(at: 10))
        guard lba > 0 else { return nil }
        return walkISODirectory(image: image, lba: lba, size: size, wanted: wanted.uppercased(), remainingDepth: 4)
    }

    /// Upper bound for one ISO9660 directory extent read into memory.
    static let maxDirectoryBytes = 2_000_000

    private static func walkISODirectory(
        image: DiscImage,
        lba: UInt32,
        size: Int,
        wanted: String,
        remainingDepth: Int
    ) -> Data? {
        // Sizes come from the disc image; a malformed record must not drive a huge allocation.
        guard remainingDepth > 0, size > 0, size < maxDirectoryBytes,
              let dir = image.read(at: UInt64(lba) * 2048, count: size), dir.count >= 1
        else { return nil }
        let dirBytes = [UInt8](dir)
        var index = 0
        var scanned = 0
        while index < dirBytes.count, scanned < 256 {
            let recLen = Int(dirBytes[index])
            if recLen == 0 {
                index = ((index / 2048) + 1) * 2048
                continue
            }
            guard recLen >= 34, index + recLen <= dirBytes.count else { break }
            let rec = Data(dirBytes[index..<(index + recLen)])
            let flags = rec[25]
            let nameLen = Int(rec[32])
            guard nameLen > 0, 33 + nameLen <= rec.count else {
                index += recLen
                scanned += 1
                continue
            }
            let name = isoName(rec.subdata(in: 33..<(33 + nameLen)))
            let childLBA = rec.u32LE(at: 2)
            let childSize = Int(rec.u32LE(at: 10))
            if flags & 0x02 != 0 {
                if name == "PSP_GAME" || name == "PSP",
                   let found = walkISODirectory(image: image, lba: childLBA, size: childSize,
                                                wanted: wanted, remainingDepth: remainingDepth - 1) {
                    return found
                }
            } else if name == wanted, childSize > 0, childSize < 2_000_000 {
                return image.read(at: UInt64(childLBA) * 2048, count: childSize)
            }
            index += recLen
            scanned += 1
        }
        return nil
    }

    private static func isoName(_ raw: Data) -> String {
        var bytes = raw
        if let semi = bytes.firstIndex(of: 0x3B) {
            bytes = bytes.prefix(upTo: semi)
        }
        return String(bytes: bytes, encoding: .ascii)?.uppercased() ?? ""
    }
}

/// An ISO's bytes, read straight from a plain image or block by block out of a CSO (CISO v1
/// deflate blocks, v2 also LZ4), so only the few sectors the PARAM.SFO lookup needs are read.
struct DiscImage {
    private let handle: FileHandle
    private let cso: (blockSize: Int, align: UInt64, version: UInt8, total: UInt64)?

    init?(handle: FileHandle) {
        self.handle = handle
        guard let header = try? handle.read(upToCount: 24) else { return nil }
        guard header.count == 24, header.prefix(4) == Data("CISO".utf8) else {
            cso = nil
            return
        }
        let total = UInt64(header.u32LE(at: 8)) | (UInt64(header.u32LE(at: 12)) << 32)
        let blockSize = Int(header.u32LE(at: 16))
        guard blockSize > 0, blockSize <= 1 << 20, blockSize % 2048 == 0 else { return nil }
        cso = (blockSize, UInt64(header[21]), header[20], total)
    }

    func read(at offset: UInt64, count: Int) -> Data? {
        guard let cso else {
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
        guard count > 0, offset < cso.total else { return nil }
        let end = min(offset + UInt64(count), cso.total)
        var out = Data()
        var block = offset / UInt64(cso.blockSize)
        while UInt64(block) * UInt64(cso.blockSize) < end {
            guard let bytes = csoBlock(block) else { return nil }
            let start = UInt64(block) * UInt64(cso.blockSize)
            let from = Int(max(offset, start) - start)
            let to = Int(min(end, start + UInt64(cso.blockSize)) - start)
            guard to <= bytes.count, from < to else { return nil }
            out.append(bytes.subdata(in: from..<to))
            block += 1
        }
        return out
    }

    private func csoBlock(_ block: UInt64) -> Data? {
        guard let cso, (try? handle.seek(toOffset: 24 + block * 4)) != nil,
              let index = try? handle.read(upToCount: 8), index.count == 8
        else { return nil }
        let entry = index.u32LE(at: 0), next = index.u32LE(at: 4)
        let start = UInt64(entry & 0x7FFF_FFFF) << cso.align
        let stop = UInt64(next & 0x7FFF_FFFF) << cso.align
        guard stop > start, stop - start <= UInt64(cso.blockSize) * 2,
              (try? handle.seek(toOffset: start)) != nil,
              let stored = try? handle.read(upToCount: Int(stop - start)), stored.count == Int(stop - start)
        else { return nil }
        let flagged = entry & 0x8000_0000 != 0
        // v1: the flag marks a block stored as is. v2: it marks LZ4; a block as big as the
        // block size is stored as is.
        if cso.version >= 2 {
            if stored.count >= cso.blockSize { return stored.prefix(cso.blockSize) }
            return Self.decode(stored, size: cso.blockSize, flagged ? COMPRESSION_LZ4_RAW : COMPRESSION_ZLIB)
        }
        return flagged ? stored : Self.decode(stored, size: cso.blockSize, COMPRESSION_ZLIB)
    }

    /// Raw deflate (Compression's ZLIB has no zlib header, as CSO blocks don't) or raw LZ4.
    private static func decode(_ data: Data, size: Int, _ algorithm: compression_algorithm) -> Data? {
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, algorithm)
            }
        }
        return written == size ? out : nil
    }
}

private extension Data {
    func u32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum PSPProductIDExtraction: Sendable, Equatable {
    case found(String)
    case notFound
    case unsupportedFormat(String)
}

/// Reads the PSP product/title ID embedded in ISO / PBP metadata. Never guesses from filenames.
public enum PSPProductIDExtractor: Sendable {
    public static func extract(from fileURL: URL) -> PSPProductIDExtraction {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "iso":
            return extractFromISO(at: fileURL)
        case "pbp":
            return extractFromPBP(at: fileURL)
        case "cso", "chd":
            return .unsupportedFormat(
                ".\(ext) images compress ISO sectors; the embedded PARAM.SFO cannot be read without full decompression."
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

    // MARK: - ISO9660

    private static func extractFromISO(at url: URL) -> PSPProductIDExtraction {
        guard let sfo = readISOFile(named: "PARAM.SFO", from: url) else { return .notFound }
        guard let id = PSPParamSFO.discID(from: sfo) else { return .notFound }
        return .found(id)
    }

    private static func readISOFile(named wanted: String, from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let sector = 2048
        let pvdOffset = UInt64(16 * sector)
        do {
            try handle.seek(toOffset: pvdOffset)
            guard let pvd = try handle.read(upToCount: sector), pvd.count >= 190 else { return nil }
            guard pvd[0] == 1, pvd[1] == 0x43, pvd[2] == 0x44, pvd[3] == 0x30, pvd[4] == 0x30, pvd[5] == 0x31 else {
                return nil
            }
            let root = pvd.subdata(in: 156..<190)
            let lba = root.u32LE(at: 2)
            let size = Int(root.u32LE(at: 10))
            guard lba > 0, size > 0, size < maxDirectoryBytes else { return nil }
            return walkISODirectory(
                handle: handle,
                lba: lba,
                size: size,
                wanted: wanted.uppercased(),
                remainingDepth: 4
            )
        } catch {
            return nil
        }
    }

    /// Upper bound for one ISO9660 directory extent read into memory.
    static let maxDirectoryBytes = 2_000_000

    private static func walkISODirectory(
        handle: FileHandle,
        lba: UInt32,
        size: Int,
        wanted: String,
        remainingDepth: Int
    ) -> Data? {
        // Sizes come from the disc image; a malformed record must not drive a huge allocation.
        guard remainingDepth > 0, size > 0, size < maxDirectoryBytes else { return nil }
        let offset = UInt64(lba) * 2048
        do {
            try handle.seek(toOffset: offset)
            guard let dir = try handle.read(upToCount: size), dir.count >= 1 else { return nil }
            var index = 0
            var scanned = 0
            while index < dir.count, scanned < 256 {
                let recLen = Int(dir[index])
                if recLen == 0 {
                    index = ((index / 2048) + 1) * 2048
                    continue
                }
                guard recLen >= 34, index + recLen <= dir.count else { break }
                let rec = dir.subdata(in: index..<(index + recLen))
                let flags = rec[25]
                let nameLen = Int(rec[32])
                guard nameLen > 0, 33 + nameLen <= rec.count else {
                    index += recLen
                    scanned += 1
                    continue
                }
                let rawName = rec.subdata(in: 33..<(33 + nameLen))
                let name = isoName(rawName)
                let childLBA = rec.u32LE(at: 2)
                let childSize = Int(rec.u32LE(at: 10))
                if flags & 0x02 != 0 {
                    if name == "PSP_GAME" || name == "PSP" {
                        if let found = walkISODirectory(
                            handle: handle,
                            lba: childLBA,
                            size: childSize,
                            wanted: wanted,
                            remainingDepth: remainingDepth - 1
                        ) {
                            return found
                        }
                    }
                } else if name == wanted, childSize > 0, childSize < 2_000_000 {
                    try handle.seek(toOffset: UInt64(childLBA) * 2048)
                    return try handle.read(upToCount: childSize)
                }
                index += recLen
                scanned += 1
            }
        } catch {
            return nil
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

private extension Data {
    func u32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

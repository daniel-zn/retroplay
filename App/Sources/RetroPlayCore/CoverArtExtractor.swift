// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Local-only cover bytes from a game file. Never fetches a network resource.
public enum CoverArtExtractor: Sendable {
    public static func extractImageData(from fileURL: URL, system: SystemID) -> Data? {
        switch system {
        case .psp:
            return extractPSP(from: fileURL)
        case .nds:
            return extractNDSBannerPNG(from: fileURL)
        case .gba, .n64:
            return nil
        }
    }

    // MARK: - PSP (PBP header or ISO9660 ICON0.PNG)

    private static func extractPSP(from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic.count == 4 else { return nil }
        if magic == Data([0x00, 0x50, 0x42, 0x50]) { // \0PBP
            return extractPBPIcon(handle: handle)
        }
        if magic == Data("CISO".utf8) {
            return nil
        }
        return extractISO9660File(named: "ICON0.PNG", from: url)
    }

    private static func extractPBPIcon(handle: FileHandle) -> Data? {
        guard let rest = try? handle.read(upToCount: 4 + 8 * 4), rest.count >= 36 else { return nil }
        // version (4) + 8 offsets. ICON0 is the second file (index 1).
        let icon0 = rest.u32LE(at: 8)
        let icon1 = rest.u32LE(at: 12)
        guard icon0 > 0, icon1 >= icon0 else { return nil }
        let size = Int(icon1 - icon0)
        guard size > 8, size < 512_000 else { return nil }
        // EBOOT.PBP can be hundreds of MB; read only the ICON0 range.
        guard (try? handle.seek(toOffset: UInt64(icon0))) != nil,
              let slice = try? handle.read(upToCount: size),
              slice.count == size
        else { return nil }
        return isPNG(slice) ? slice : nil
    }

    private static func extractISO9660File(named wanted: String, from url: URL) -> Data? {
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
                } else if name == wanted, childSize > 8, childSize < 512_000 {
                    try handle.seek(toOffset: UInt64(childLBA) * 2048)
                    if let bytes = try handle.read(upToCount: childSize), isPNG(bytes) {
                        return bytes
                    }
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
        if let semi = bytes.firstIndex(of: 0x3B) { // ';'
            bytes = bytes.prefix(upTo: semi)
        }
        return String(bytes: bytes, encoding: .ascii)?.uppercased() ?? ""
    }

    // MARK: - NDS banner → 32×32 PNG

    private static func extractNDSBannerPNG(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count >= 0x6C else {
            return nil
        }
        let bannerOffset = Int(data.u32LE(at: 0x68))
        guard bannerOffset > 0, bannerOffset + 0x240 <= data.count else { return nil }
        let bitmap = data.subdata(in: (bannerOffset + 0x20)..<(bannerOffset + 0x220))
        let palette = data.subdata(in: (bannerOffset + 0x220)..<(bannerOffset + 0x240))
        guard let png = ndsBannerPNG(bitmap: bitmap, palette: palette) else { return nil }
        return png
    }

    private static func ndsBannerPNG(bitmap: Data, palette: Data) -> Data? {
        var rgba = [UInt8](repeating: 0, count: 32 * 32 * 4)
        var colors = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 16)
        for i in 0..<16 {
            let entry = UInt16(palette[i * 2]) | (UInt16(palette[i * 2 + 1]) << 8)
            let r = UInt8(((entry & 0x1F) * 255) / 31)
            let g = UInt8((((entry >> 5) & 0x1F) * 255) / 31)
            let b = UInt8((((entry >> 10) & 0x1F) * 255) / 31)
            colors[i] = (r, g, b)
        }
        // 4×4 tiles of 8×8, 4bpp.
        for tileY in 0..<4 {
            for tileX in 0..<4 {
                let tileIndex = tileY * 4 + tileX
                let tileOff = tileIndex * 32
                for py in 0..<8 {
                    for px in 0..<8 {
                        let pixelIndex = py * 8 + px
                        let byte = bitmap[tileOff + pixelIndex / 2]
                        let nibble = pixelIndex % 2 == 0 ? byte & 0x0F : byte >> 4
                        let x = tileX * 8 + px
                        let y = tileY * 8 + py
                        let dest = (y * 32 + x) * 4
                        if nibble == 0 {
                            rgba[dest + 3] = 0
                        } else {
                            let c = colors[Int(nibble)]
                            rgba[dest] = c.0
                            rgba[dest + 1] = c.1
                            rgba[dest + 2] = c.2
                            rgba[dest + 3] = 255
                        }
                    }
                }
            }
        }
        return CoverArtPNG.encodeRGBA(width: 32, height: 32, pixels: rgba)
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
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

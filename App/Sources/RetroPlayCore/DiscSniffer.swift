// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Picks the system for a file whose extension two systems share, from the file's own bytes:
/// `iso` / `chd` / `pbp` (PSP or PS1) and `bin` (a Genesis ROM or a PS1 disc track).
/// Reads at most a few kilobytes; never the whole file.
public enum DiscSniffer {
    public static func system(forFileAt url: URL, fileExtension ext: String) -> SystemID? {
        let ext = ext.lowercased()
        let candidates = SystemID.allCases.filter { $0.fileExtensions.contains(ext) }
        guard candidates.count > 1 || ext == "exe" else { return candidates.first }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Only PS1 programs: an .exe is anything from a Windows app to a PS-X EXE.
        if ext == "exe" {
            return read(handle, at: 0, count: 8) == Data("PS-X EXE".utf8) ? .ps1 : nil
        }
        switch ext {
        case "bin": return sniffBin(handle)
        case "iso": return sniffISO(handle) ?? .psp
        case "pbp": return sniffPBP(handle) ?? .psp
        case "chd": return sniffCHD(handle) ?? .psp
        default: return candidates.first
        }
    }

    /// Raw CD sectors start with this sync pattern.
    static let cdSync = Data([0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00])

    static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count),
              data.count == count
        else { return nil }
        return data
    }

    /// Genesis ROMs carry "SEGA" in the header at 0x100; a PS1 track is raw CD sectors.
    static func sniffBin(_ handle: FileHandle) -> SystemID? {
        if let header = read(handle, at: 0x100, count: 16),
           String(decoding: header, as: UTF8.self).contains("SEGA") {
            return .genesis
        }
        if let sync = read(handle, at: 0, count: 12), sync == cdSync {
            return .ps1
        }
        return nil
    }

    /// ISO 9660 system identifier: "PSP GAME" or "PLAYSTATION" (2048-byte sectors), or a raw
    /// 2352-byte-sector image, which only PS1 uses.
    static func sniffISO(_ handle: FileHandle) -> SystemID? {
        if let sync = read(handle, at: 0, count: 12), sync == cdSync { return .ps1 }
        guard let pvd = read(handle, at: 0x8000, count: 40),
              String(decoding: pvd[pvd.startIndex + 1 ..< pvd.startIndex + 6], as: UTF8.self) == "CD001"
        else { return nil }
        let systemID = String(decoding: pvd[pvd.startIndex + 8 ..< pvd.startIndex + 40], as: UTF8.self)
        if systemID.hasPrefix("PSP GAME") { return .psp }
        if systemID.hasPrefix("PLAYSTATION") { return .ps1 }
        return nil
    }

    /// PBP: the DATA.PSAR section of a converted PS1 game starts "PSISOIMG" / "PSTITLEIMG".
    static func sniffPBP(_ handle: FileHandle) -> SystemID? {
        guard let header = read(handle, at: 0, count: 40),
              header.prefix(4) == Data([0x00, 0x50, 0x42, 0x50])
        else { return nil }
        let psarOffset = header[header.startIndex + 36 ..< header.startIndex + 40]
            .enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * UInt64($1.offset))) }
        guard let psar = read(handle, at: psarOffset, count: 10) else { return .psp }
        let magic = String(decoding: psar, as: UTF8.self)
        return magic.hasPrefix("PSISOIMG") || magic.hasPrefix("PSTITLEIMG") ? .ps1 : .psp
    }

    /// CHD: CD images carry CD track metadata (made with `chdman createcd`), PSP UMDs DVD
    /// metadata (`createdvd`).
    static func sniffCHD(_ handle: FileHandle) -> SystemID? {
        guard let header = read(handle, at: 0, count: 64),
              header.prefix(8) == Data("MComprHD".utf8)
        else { return nil }
        let version = bigEndian(header, 12, 4)
        let metaOffset: UInt64
        switch version {
        case 5: metaOffset = bigEndian(header, 48, 8)
        case 3, 4: metaOffset = bigEndian(header, 36, 8)
        default: return nil
        }
        guard metaOffset > 0, let tag = read(handle, at: metaOffset, count: 4) else { return nil }
        switch String(decoding: tag, as: UTF8.self) {
        case "CHT2", "CHTR", "CHCD": return .ps1
        case "DVD ": return .psp
        default: return nil
        }
    }

    static func bigEndian(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        data[data.startIndex + offset ..< data.startIndex + offset + count]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

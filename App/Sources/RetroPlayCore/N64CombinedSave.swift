// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Mupen64Plus-Next's one save file per game (`.srm`): the core's `save_memory_data`
/// (libretro/libretro_memory.h), written out as is. Loose saves from other emulators and flash
/// carts (.eep, .mpk, .sra, .fla) are each one of its regions; importing one writes only that
/// region and keeps the rest. See docs/N64-SAVES.md for the layout and the byte orders.
public enum N64CombinedSave {
    public static let eepromSize = 0x800
    public static let pakSize = 0x8000
    public static let pakCount = 4
    public static let sramSize = 0x8000
    public static let flashSize = 0x20000

    public static let eepromOffset = 0
    public static let pakOffset = eepromOffset + eepromSize
    public static let sramOffset = pakOffset + pakCount * pakSize
    public static let flashOffset = sramOffset + sramSize
    public static let size = flashOffset + flashSize

    /// One part of the combined save.
    public enum Region: Sendable, Hashable, Comparable {
        case eeprom
        /// 1…4.
        case controllerPak(Int)
        case sram
        case flashRAM

        public var title: String {
            switch self {
            case .eeprom: "EEPROM"
            case .controllerPak(let index): "Controller Pak \(index)"
            case .sram: "SRAM"
            case .flashRAM: "FlashRAM"
            }
        }

        public var offset: Int {
            switch self {
            case .eeprom: eepromOffset
            case .controllerPak(let index): pakOffset + (index - 1) * pakSize
            case .sram: sramOffset
            case .flashRAM: flashOffset
            }
        }

        public var length: Int {
            switch self {
            case .eeprom: eepromSize
            case .controllerPak: pakSize
            case .sram: sramSize
            case .flashRAM: flashSize
            }
        }

        private var order: Int {
            switch self {
            case .eeprom: 0
            case .controllerPak(let index): index
            case .sram: 10
            case .flashRAM: 11
            }
        }

        public static func < (lhs: Region, rhs: Region) -> Bool { lhs.order < rhs.order }
    }

    /// One region's bytes, already in the order the core keeps them.
    public struct Part: Sendable, Equatable {
        public let region: Region
        public let bytes: Data
        /// Said in the summary when the file's byte order couldn't be told and was assumed.
        public let note: String?

        public init(region: Region, bytes: Data, note: String? = nil) {
            self.region = region
            self.bytes = bytes
            self.note = note
        }
    }

    public enum ImportError: Error, LocalizedError, Equatable {
        case wrongSize(extension: String, bytes: Int, expected: String)
        case notAControllerPak

        public var errorDescription: String? {
            switch self {
            case .wrongSize(let ext, let bytes, let expected):
                "A .\(ext) save is \(expected); this one is \(bytes) bytes."
            case .notAControllerPak:
                "Not a Controller Pak: its ID block doesn't check out in either byte order."
            }
        }
    }

    public static let looseExtensions: Set<String> = ["eep", "mpk", "sra", "fla"]

    /// Folder names that mean a flash cart's save (big-endian SRAM / FlashRAM, as the cartridge
    /// holds it); otherwise an emulator's (32-bit words swapped, the core's own order).
    static let flashCartFolderHints = ["ed64", "everdrive", "summercart", "sc64", "64drive"]

    static let assumedOrderNote = "Byte order assumed from an emulator (Project64, Mupen64Plus); a flash cart's save would be put in its own folder."

    /// The regions a loose file holds, in the core's order. `name` is the file's base name (a
    /// Controller Pak's "…_2" picks pak 2); `folders` are the folder names above it.
    public static func parts(extension rawExt: String, data: Data, name: String, folders: [String]) throws -> [Part] {
        let ext = rawExt.lowercased()
        switch ext {
        case "eep":
            // 4 Kbit (512 bytes) or 16 Kbit (2 KiB), a byte array in every emulator and cart.
            guard data.count == 0x200 || data.count == 0x800 else {
                throw ImportError.wrongSize(extension: ext, bytes: data.count, expected: "512 bytes or 2 KiB")
            }
            return [Part(region: .eeprom, bytes: data)]
        case "mpk":
            // One pak (32 KiB) or four (128 KiB: Mupen64Plus standalone keeps all four).
            if data.count == pakSize {
                return [Part(region: .controllerPak(pakIndex(fromName: name)), bytes: try pakBytes(data))]
            }
            guard data.count == pakCount * pakSize else {
                throw ImportError.wrongSize(extension: ext, bytes: data.count, expected: "32 KiB (one Controller Pak) or 128 KiB (four)")
            }
            var parts: [Part] = []
            for index in 0..<pakCount {
                let pak = data.subdata(in: index * pakSize..<(index + 1) * pakSize)
                // A slot that was never formatted (all zero) is left as it is here.
                guard let bytes = try? pakBytes(pak) else { continue }
                parts.append(Part(region: .controllerPak(index + 1), bytes: bytes))
            }
            guard !parts.isEmpty else { throw ImportError.notAControllerPak }
            return parts
        case "sra", "fla":
            let region: Region = ext == "sra" ? .sram : .flashRAM
            guard data.count == region.length else {
                throw ImportError.wrongSize(extension: ext, bytes: data.count, expected: ext == "sra" ? "32 KiB" : "128 KiB")
            }
            let cart = folders.contains { folder in
                let lower = folder.lowercased()
                return flashCartFolderHints.contains { lower.contains($0) }
            }
            return cart
                ? [Part(region: region, bytes: swappingWords(data))]
                : [Part(region: region, bytes: data, note: assumedOrderNote)]
        default:
            return []
        }
    }

    /// "Mario Kart 64_2" (or " 2", "-2") is pak 2; anything else pak 1.
    static func pakIndex(fromName name: String) -> Int {
        if let match = name.range(of: #"[ _-]([1-4])$"#, options: .regularExpression),
           let digit = Int(name[match].dropFirst()) {
            return digit
        }
        return 1
    }

    /// The title a Controller Pak file names ("Mario Kart 64_2" → "Mario Kart 64").
    static func pakTitle(fromName name: String) -> String {
        guard let match = name.range(of: #"[ _-][1-4]$"#, options: .regularExpression) else { return name }
        return String(name[..<match.lowerBound])
    }

    /// A pak in the core's order: as is when its ID block checks out (every emulator writes
    /// paks as the N64 does, big-endian); with its 32-bit words swapped when only that checks out.
    static func pakBytes(_ data: Data) throws -> Data {
        if isFormattedPak(data) { return data }
        let swapped = swappingWords(data)
        if isFormattedPak(swapped) { return swapped }
        throw ImportError.notAControllerPak
    }

    /// The pak's ID block (page 0, 32-byte block 1): its two checksums, as the core computes
    /// them (mempak.c checksum_id_block).
    static func isFormattedPak(_ data: Data) -> Bool {
        guard data.count >= 0x40 else { return false }
        let block = [UInt8](data[data.startIndex + 0x20..<data.startIndex + 0x40])
        var sum: UInt16 = 0
        for i in stride(from: 0, to: 28, by: 2) {
            sum &+= UInt16(block[i]) << 8 | UInt16(block[i + 1])
        }
        let stored = UInt16(block[28]) << 8 | UInt16(block[29])
        let storedInverse = UInt16(block[30]) << 8 | UInt16(block[31])
        return stored == sum && storedInverse == 0xFFF2 &- sum
    }

    /// Each 32-bit word's bytes reversed (big-endian ↔ the little-endian words emulators keep).
    static func swappingWords(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        var i = 0
        while i + 3 < bytes.count {
            bytes.swapAt(i, i + 3)
            bytes.swapAt(i + 1, i + 2)
            i += 4
        }
        return Data(bytes)
    }

    /// A combined save with nothing in it, as the core starts one (libretro.c
    /// format_saved_memory): EEPROM, SRAM and FlashRAM all 0xFF, each Controller Pak formatted
    /// with its own serial.
    public static func blank() -> Data {
        var data = Data(repeating: 0xFF, count: size)
        for index in 1...pakCount {
            var serial: [UInt32] = []
            for _ in 0..<6 { serial.append(UInt32.random(in: .min ... .max)) }
            data.replaceSubrange(Region.controllerPak(index).offset..<Region.controllerPak(index).offset + pakSize,
                                 with: formattedPak(serial: serial))
        }
        return data
    }

    /// An empty Controller Pak (mempak.c format_mempak: device 0x0001, 1 bank, version 0).
    static func formattedPak(serial: [UInt32]) -> Data {
        var pak = [UInt8](repeating: 0, count: pakSize)
        func put16(_ value: UInt16, at offset: Int) {
            pak[offset] = UInt8(value >> 8)
            pak[offset + 1] = UInt8(value & 0xFF)
        }
        // Page 0, block 1: the ID block, then its backups in blocks 3, 4 and 6.
        var id = [UInt8](repeating: 0, count: 32)
        for (i, word) in serial.prefix(6).enumerated() {
            id[i * 4] = UInt8(word >> 24); id[i * 4 + 1] = UInt8((word >> 16) & 0xFF)
            id[i * 4 + 2] = UInt8((word >> 8) & 0xFF); id[i * 4 + 3] = UInt8(word & 0xFF)
        }
        id[24] = 0x00; id[25] = 0x01   // device ID
        id[26] = 0x01                  // banks
        id[27] = 0x00                  // version
        var sum: UInt16 = 0
        for i in stride(from: 0, to: 28, by: 2) { sum &+= UInt16(id[i]) << 8 | UInt16(id[i + 1]) }
        id[28] = UInt8(sum >> 8); id[29] = UInt8(sum & 0xFF)
        let inverse = 0xFFF2 &- sum
        id[30] = UInt8(inverse >> 8); id[31] = UInt8(inverse & 0xFF)
        for block in [1, 3, 4, 6] { pak.replaceSubrange(block * 32..<block * 32 + 32, with: id) }
        // Page 1: the index table; pages 0-4 reserved, 5…127 empty (0x0003), the checksum of
        // the normal nodes in byte 1. Page 2 backs it up.
        let page1 = 256
        for i in 5..<128 { put16(0x0003, at: page1 + 2 * i) }
        var checksum = 0
        for i in (page1 + 10)..<(page1 + 256) { checksum += Int(pak[i]) }
        pak[page1 + 1] = UInt8(checksum & 0xFF)
        pak.replaceSubrange(512..<768, with: pak[page1..<page1 + 256])
        return Data(pak)
    }

    /// `parts` written over `existing` (or a blank save when there's none or it's the wrong
    /// size); every other region is kept. A short EEPROM (4 Kbit) leaves the rest of its region.
    public static func merge(_ parts: [Part], into existing: Data?) -> Data {
        var data = existing.flatMap { $0.count == size ? $0 : nil } ?? blank()
        for part in parts {
            let start = part.region.offset
            data.replaceSubrange(start..<start + min(part.bytes.count, part.region.length), with: part.bytes.prefix(part.region.length))
        }
        return data
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Parses PSP `PARAM.SFO` bytes and reads the `DISC_ID` product/title identifier.
public enum PSPParamSFO: Sendable {
    public static func discID(from sfoData: Data) -> String? {
        guard let value = value(forKey: "DISC_ID", in: sfoData) else { return nil }
        guard let raw = String(bytes: value.prefix(while: { $0 != 0 }), encoding: .ascii), !raw.isEmpty else { return nil }
        return PSPProductIDNormalizer.normalize(raw)
    }

    /// The data files a save slot's PARAM.SFO lists (SAVEDATA_FILE_LIST: 32-byte entries, a
    /// 13-byte NUL-padded name then a hash). Only plain names: nothing with a path in it.
    static func saveDataFiles(from sfoData: Data) -> [String] {
        guard let list = value(forKey: "SAVEDATA_FILE_LIST", in: sfoData) else { return [] }
        let bytes = [UInt8](list)
        return stride(from: 0, to: bytes.count, by: 32).compactMap { start in
            let name = bytes[start..<min(start + 13, bytes.count)].prefix(while: { $0 != 0 })
            guard let text = String(bytes: name, encoding: .ascii), !text.isEmpty,
                  text != ".", text != "..", !text.contains("/") else { return nil }
            return text
        }
    }

    /// The bytes stored under `key` (its used length), nil if absent or malformed.
    static func value(forKey wanted: String, in sfoData: Data) -> Data? {
        guard sfoData.count >= 20 else { return nil }
        guard sfoData.u32LE(at: 0) == 0x46535000 else { return nil } // "\0PSF"

        let keyTableOffset = Int(sfoData.u32LE(at: 8))
        let dataTableOffset = Int(sfoData.u32LE(at: 12))
        let indexCount = Int(sfoData.u32LE(at: 16))
        guard indexCount > 0, indexCount < 512 else { return nil }
        guard keyTableOffset >= 20, dataTableOffset >= keyTableOffset else { return nil }

        for index in 0..<indexCount {
            let entryOffset = 20 + index * 16
            guard entryOffset + 16 <= sfoData.count else { return nil }

            let keyOffset = Int(sfoData.u16LE(at: entryOffset))
            let dataLength = Int(sfoData.u32LE(at: entryOffset + 4))
            let dataOffset = Int(sfoData.u32LE(at: entryOffset + 12))

            let keyStart = keyTableOffset + keyOffset
            guard keyStart < sfoData.count else { continue }
            guard let keyEnd = sfoData[keyStart...].firstIndex(of: 0) else { continue }
            let key = String(data: sfoData[keyStart..<keyEnd], encoding: .ascii) ?? ""
            guard key == wanted else { continue }

            let valueStart = dataTableOffset + dataOffset
            guard valueStart < sfoData.count, dataLength > 0 else { return nil }
            let valueEnd = min(valueStart + dataLength, sfoData.count)
            return Data(sfoData[valueStart..<valueEnd])
        }
        return nil
    }
}

private extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Parses PSP `PARAM.SFO` bytes and reads the `DISC_ID` product/title identifier.
public enum PSPParamSFO: Sendable {
    public static func discID(from sfoData: Data) -> String? {
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
            guard key == "DISC_ID" else { continue }

            let valueStart = dataTableOffset + dataOffset
            guard valueStart < sfoData.count, dataLength > 0 else { return nil }
            let valueEnd = min(valueStart + dataLength, sfoData.count)
            let valueBytes = sfoData[valueStart..<valueEnd]
            let trimmed = valueBytes.prefix(while: { $0 != 0 })
            guard let raw = String(bytes: trimmed, encoding: .ascii), !raw.isEmpty else { return nil }
            return PSPProductIDNormalizer.normalize(raw)
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

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Normalizes PSP product / title IDs to the SAVEDATA folder form (uppercase, no hyphen).
public enum PSPProductIDNormalizer: Sendable {
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let compact = trimmed.uppercased().replacingOccurrences(of: "-", with: "")
        guard SaveGameImporter.isValidPSPGameID(compact) else { return nil }
        return compact
    }
}

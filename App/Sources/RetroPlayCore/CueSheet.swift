// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A PS1 `.cue` sheet names the `.bin` track files that hold the disc. RetroPlay keeps them
/// next to the sheet, so import, the Games/ scan and deletion treat them as one game.
public enum CueSheet {
    /// File names the sheet's `FILE` lines reference, in order, as safe leaf names.
    public static func referencedFiles(in text: String) -> [String] {
        var names: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("FILE ") else { continue }
            var rest = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let name: String
            if rest.hasPrefix("\"") {
                rest.removeFirst()
                guard let close = rest.firstIndex(of: "\"") else { continue }
                name = String(rest[..<close])
            } else {
                name = rest.split(separator: " ").first.map(String.init) ?? ""
            }
            // Sheets made on Windows may use backslashes; only the leaf name is used.
            let leaf = name.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/").last.map(String.init) ?? ""
            if SavePaths.isSafeFileName(leaf), !names.contains(leaf) {
                names.append(leaf)
            }
        }
        return names
    }

    public static func referencedFiles(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count < 1_000_000 else {
            return []
        }
        return referencedFiles(in: String(decoding: data, as: UTF8.self))
    }
}

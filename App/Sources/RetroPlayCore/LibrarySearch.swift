// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Library search: every query word must appear in the title, ignoring case, accents, width
/// and punctuation ("pokemon" finds "Pokémon", "zelda minish" finds "Zelda - The Minish Cap").
/// A query that is exactly a system's name (or short name / core) lists that system's games.
public enum LibrarySearch {
    public static func matches(
        _ game: LibraryGame,
        query: String,
        systemNames: (SystemID) -> [String] = { [$0.displayName, $0.defaultCoreName] }
    ) -> Bool {
        let words = words(in: query)
        guard !words.isEmpty else { return false }
        let title = Self.words(in: game.displayName).joined(separator: " ")
        if words.allSatisfy({ title.contains($0) }) { return true }
        let whole = words.joined(separator: " ")
        return systemNames(game.systemID)
            .map { Self.words(in: $0).joined(separator: " ") }
            .contains(whole)
    }

    /// Lowercased words with accents, width and punctuation folded away.
    public static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

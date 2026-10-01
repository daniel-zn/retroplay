// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Recent search queries for the Search tab, newest first, stored as a JSON string.
public enum RecentSearches {
    public static let limit = 10

    /// `list` with `query` moved (or added) to the front. Blank queries are ignored, and a
    /// query that differs only in case, accents or punctuation replaces the older one.
    public static func adding(_ query: String, to list: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = LibrarySearch.words(in: trimmed)
        guard !key.isEmpty else { return list }
        let rest = list.filter { LibrarySearch.words(in: $0) != key }
        return Array(([trimmed] + rest).prefix(limit))
    }

    public static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return list
    }

    public static func encode(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

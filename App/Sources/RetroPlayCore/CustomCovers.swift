// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Pictures the player adds as covers: an image named like a game's file ("Crush ULUS10238.jpg"
/// for "Crush ULUS10238.iso"), picked in Import or dropped into Files → RetroPlay → Games. They
/// win over downloaded box art and art from the game file.
public enum CustomCovers {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    public static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// The library game a picture belongs to: the same file name apart from the extension
    /// (ignoring case), wherever the game sits in Games/.
    public static func game(forImageNamed name: String, in games: [LibraryGame]) -> LibraryGame? {
        let base = (name as NSString).deletingPathExtension.lowercased()
        return games.first { game in
            let leaf = (game.relativePath as NSString).lastPathComponent
            return (leaf as NSString).deletingPathExtension.lowercased() == base
        }
    }

    /// Pictures in Games/ and in each game's own folder (PS1 discs), with when they last changed.
    static func imagesInGamesFolder(_ games: URL, fileManager: FileManager) -> [(url: URL, modified: Date)] {
        var found: [(URL, Date)] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let top = try? fileManager.contentsOfDirectory(at: games, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles])
        else { return [] }
        var candidates = top
        for item in top where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            candidates += (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        }
        for url in candidates where isImage(url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            found.append((url, modified ?? .distantPast))
        }
        return found
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import UIKit
import RetroPlayCore

/// A library cover: a full box cover (downloaded box art or the player's own picture), or art
/// read from the game file (a PSP / DS icon).
struct CoverArt {
    let image: UIImage
    /// A whole cover with its own shape, drawn edge to edge; icons are fitted instead.
    let isBoxArt: Bool
}

/// In-memory cover cache so grid tiles do not re-read JPEGs on every SwiftUI pass.
@MainActor
final class CoverArtImageCache: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()
    private var boxArt: Set<UUID> = []
    /// Bumped when a cover changes on disk (box art downloaded), so tiles redraw.
    @Published private(set) var revision = 0
    /// Games with no cover (all GBA / N64, some DS / PSP): don't re-read the disk every render.
    private var missing: Set<UUID> = []
    private let covers: CoverArtStore

    init(covers: CoverArtStore = CoverArtStore()) {
        self.covers = covers
        cache.countLimit = 256
    }

    func cover(for game: LibraryGame) -> CoverArt? {
        image(for: game).map { CoverArt(image: $0, isBoxArt: boxArt.contains(game.id)) }
    }

    func image(for game: LibraryGame) -> UIImage? {
        let key = game.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if missing.contains(game.id) { return nil }
        guard let url = covers.displayableCoverURL(forGameID: game.id),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else {
            missing.insert(game.id)
            return nil
        }
        if [.boxArt, .custom].contains(covers.origin(forGameID: game.id)) {
            boxArt.insert(game.id)
        } else {
            boxArt.remove(game.id)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The player's pictures replaced covers: drop everything cached and redraw.
    func coversReplaced() {
        removeAll()
        revision += 1
    }

    /// A new cover was written for this game: drop the old one and redraw.
    func coverChanged(gameID: UUID) {
        remove(gameID: gameID)
        revision += 1
    }

    func remove(gameID: UUID) {
        cache.removeObject(forKey: gameID.uuidString as NSString)
        missing.remove(gameID)
    }

    /// Covers can be written after a tile first renders (folder scan, import); retry then.
    func forgetMissing() {
        missing.removeAll()
    }

    func removeAll() {
        cache.removeAllObjects()
        missing.removeAll()
    }
}

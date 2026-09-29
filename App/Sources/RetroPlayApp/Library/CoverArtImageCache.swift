// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import UIKit
import RetroPlayCore

/// In-memory cover cache so grid tiles do not re-read JPEGs on every SwiftUI pass.
@MainActor
final class CoverArtImageCache: ObservableObject {
    private let cache = NSCache<NSString, UIImage>()
    private let covers: CoverArtStore

    init(covers: CoverArtStore = CoverArtStore()) {
        self.covers = covers
        cache.countLimit = 256
    }

    func image(for game: LibraryGame) -> UIImage? {
        let key = game.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = covers.displayableCoverURL(forGameID: game.id),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    func remove(gameID: UUID) {
        cache.removeObject(forKey: gameID.uuidString as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

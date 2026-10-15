// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

/// Fills in box art for library games from the libretro thumbnail server, one pass at a time.
/// Each game is looked up once (found or not) and again only after `BoxArtIndexCache.maxAge`,
/// so a library without matches doesn't go back to the network on every launch.
@MainActor
final class BoxArtUpdater {
    /// Settings → Library → Download Box Art.
    static let enabledKey = "retroplay.downloadBoxArt"

    private let covers: CoverArtStore
    private let indexCache: BoxArtIndexCache
    private let downloader: BoxArtDownloader
    private var running = false
    /// The newest game list; a call while a pass runs only updates it and asks for one more pass.
    private var latest: [LibraryGame] = []
    private var again = false

    init(
        covers: CoverArtStore = CoverArtStore(),
        indexCache: BoxArtIndexCache = BoxArtIndexCache(),
        downloader: BoxArtDownloader = BoxArtDownloader()
    ) {
        self.covers = covers
        self.indexCache = indexCache
        self.downloader = downloader
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Looks up every game that has no box art yet. `changed` runs for each cover written.
    func update(_ games: [LibraryGame], changed: @escaping (UUID) -> Void) async {
        guard Self.isEnabled else { return }
        latest = games
        guard !running else {
            again = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            again = false
            await pass(latest, changed: changed)
        } while again && Self.isEnabled
    }

    /// Settings turned box art back on: try every game again.
    func forgetLookups() {
        indexCache.forgetLookups()
    }

    private func pass(_ games: [LibraryGame], changed: @escaping (UUID) -> Void) async {
        let now = Date()
        let lookedUp = indexCache.lookedUp()
        let pending = games.filter { game in
            covers.origin(forGameID: game.id) != .boxArt
                && (lookedUp[game.id].map { now.timeIntervalSince($0) > BoxArtIndexCache.maxAge } ?? true)
        }
        for (system, systemGames) in Dictionary(grouping: pending, by: \.systemID) {
            guard Self.isEnabled, let names = await names(for: system) else { continue }
            var done: [UUID] = []
            for game in systemGames {
                guard Self.isEnabled else { break }
                let fileName = (game.relativePath as NSString).lastPathComponent
                guard let name = BoxArt.bestMatch(title: game.displayName, fileName: fileName, in: names) else {
                    done.append(game.id)
                    continue
                }
                // A failed download (offline) isn't recorded, so the next pass tries again.
                guard let data = try? await downloader.image(for: system, name: name) else { continue }
                if (try? covers.installBoxArt(data, forGameID: game.id)) == true {
                    changed(game.id)
                }
                done.append(game.id)
            }
            indexCache.markLookedUp(done)
        }
    }

    private func names(for system: SystemID) async -> [String]? {
        if let cached = indexCache.names(for: system) { return cached }
        guard let names = try? await downloader.index(for: system), !names.isEmpty else { return nil }
        indexCache.store(names, for: system)
        return names
    }
}

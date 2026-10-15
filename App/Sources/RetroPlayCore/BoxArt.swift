// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Box art from the libretro thumbnail server (thumbnails.libretro.com, the covers RetroArch
/// shows), matched by the game's title. Each system's folder lists PNGs named after the
/// No-Intro / Redump release ("Legend of Zelda, The - Ocarina of Time (USA).png").
/// Only an exact title match is used: a missing cover beats somebody else's.
public enum BoxArt {
    public static let server = URL(string: "https://thumbnails.libretro.com/")!

    /// The server's folder for each system.
    public static func folder(for system: SystemID) -> String {
        switch system {
        case .gba: return "Nintendo - Game Boy Advance"
        case .n64: return "Nintendo - Nintendo 64"
        case .nds: return "Nintendo - Nintendo DS"
        case .psp: return "Sony - PlayStation Portable"
        case .nes: return "Nintendo - Nintendo Entertainment System"
        case .snes: return "Nintendo - Super Nintendo Entertainment System"
        case .genesis: return "Sega - Mega Drive - Genesis"
        case .atari7800: return "Atari - 7800"
        case .ps1: return "Sony - PlayStation"
        }
    }

    public static func indexURL(for system: SystemID) -> URL {
        server.appendingPathComponent(folder(for: system), isDirectory: true)
            .appendingPathComponent("Named_Boxarts", isDirectory: true)
    }

    public static func imageURL(for system: SystemID, name: String) -> URL {
        indexURL(for: system).appendingPathComponent(name + ".png", isDirectory: false)
    }

    /// Release names (without ".png") listed in a folder's HTML index.
    public static func parseIndex(_ html: String) -> [String] {
        var names: [String] = []
        var rest = html[...]
        while let start = rest.range(of: "href=\"") {
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            let href = String(rest[..<end])
            rest = rest[end...]
            guard href.hasSuffix(".png"), !href.contains("/"),
                  let decoded = href.removingPercentEncoding
            else { continue }
            names.append(String(decoded.dropLast(4)))
        }
        return names
    }

    // MARK: - Matching

    /// The best release for a game: an exact title match, preferring the region named in
    /// the file name, then USA, World, Europe, Japan; never betas, demos or re-releases.
    public static func bestMatch(title: String, fileName: String, in names: [String]) -> String? {
        let wanted = Set([normalizedTitle(title), normalizedTitle(fileName)].filter { !$0.isEmpty })
        let fileTags = tags(of: (fileName as NSString).deletingPathExtension)
        let matches = names.filter { wanted.contains(normalizedTitle($0)) }
        return matches.min { score($0, fileTags: fileTags) < score($1, fileTags: fileTags) }
    }

    /// Title words only: no bracketed tags, case, punctuation, articles or "&" / "and" differences.
    public static func normalizedTitle(_ name: String) -> String {
        var s = stripExtension(name)
        s = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        s = s.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        s = s.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        let words = s.split(separator: " ").filter { $0 != "the" && $0 != "a" && $0 != "an" }
        return words.joined(separator: " ")
    }

    /// Drops a ROM file extension ("Game.gba"), but keeps dots that are part of a title
    /// ("Super Mario Bros. 3").
    static func stripExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let known = Set(SystemID.allCases.flatMap(\.fileExtensions))
        return known.contains(ext) ? (name as NSString).deletingPathExtension : name
    }

    static func tags(of name: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"[\(\[]([^\)\]]*)[\)\]]"#)
        let range = NSRange(name.startIndex..., in: name)
        return pattern.matches(in: name, range: range).compactMap {
            Range($0.range(at: 1), in: name).map { String(name[$0]).lowercased() }
        }
    }

    private static let unwanted = [
        "beta", "proto", "demo", "sample", "kiosk", "debug", "virtual console", "switch online",
        "gamecube", "wii", "collection", "pirate", "hack", "aftermarket", "unl", "promo",
    ]

    /// Lower is better.
    static func score(_ name: String, fileTags: [String]) -> Int {
        let nameTags = tags(of: name)
        var score = 0
        if nameTags.contains(where: { tag in unwanted.contains { tag.contains($0) } }) { score += 1000 }
        let regions = nameTags.first.map { $0 } ?? ""
        let fileRegion = fileTags.first { tag in
            ["usa", "world", "europe", "japan", "australia", "korea", "france", "germany", "spain", "italy"]
                .contains { tag.contains($0) }
        }
        if let fileRegion, regions == fileRegion {
            score += 0
        } else if regions.contains("usa") {
            score += 10
        } else if regions.contains("world") {
            score += 20
        } else if regions.contains("europe") || regions.contains("australia") {
            score += 30
        } else if regions.contains("japan") {
            score += 40
        } else {
            score += 50
        }
        if nameTags.contains(where: { $0.hasPrefix("rev") }) { score += 1 }
        return score + max(0, nameTags.count - 1)
    }
}

/// Cached copy of each system's box-art list (Application Support/Cache/boxart), refreshed
/// after `maxAge`, and the games already looked up so they aren't fetched on every launch.
public struct BoxArtIndexCache {
    public static let maxAge: TimeInterval = 30 * 24 * 3600
    let directory: URL
    let fileManager: FileManager

    public init(paths: SavePaths = SavePaths(), fileManager: FileManager = .default) {
        directory = paths.cacheDirectory.appendingPathComponent("boxart", isDirectory: true)
        self.fileManager = fileManager
    }

    private func indexURL(_ system: SystemID) -> URL {
        directory.appendingPathComponent("\(system.rawValue).json")
    }

    private var lookedUpURL: URL { directory.appendingPathComponent("looked-up.json") }

    /// The cached list when it's younger than `maxAge`.
    public func names(for system: SystemID, now: Date = Date()) -> [String]? {
        let url = indexURL(system)
        guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              now.timeIntervalSince(modified) < Self.maxAge,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    public func store(_ names: [String], for system: SystemID) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(names).write(to: indexURL(system), options: .atomic)
    }

    /// When each game was last looked up (found or not), by game ID.
    public func lookedUp() -> [UUID: Date] {
        guard let data = try? Data(contentsOf: lookedUpURL),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    public func markLookedUp(_ ids: [UUID], at date: Date = Date()) {
        var all = lookedUp()
        for id in ids { all[id] = date }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = Dictionary(uniqueKeysWithValues: all.map { ($0.key.uuidString, $0.value) })
        try? JSONEncoder().encode(raw).write(to: lookedUpURL, options: .atomic)
    }

    /// Forget every lookup, so the next pass tries all games again.
    public func forgetLookups() {
        try? fileManager.removeItem(at: lookedUpURL)
    }
}

/// Looks up and downloads box art for library games. Network work only; the caller decides
/// when (and whether) it runs.
public struct BoxArtDownloader: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    let fetch: Fetch

    public init(fetch: @escaping Fetch = BoxArtDownloader.urlSessionFetch) {
        self.fetch = fetch
    }

    public static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("RetroPlay", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    public func index(for system: SystemID) async throws -> [String] {
        let data = try await fetch(BoxArt.indexURL(for: system))
        return BoxArt.parseIndex(String(decoding: data, as: UTF8.self))
    }

    /// The cover image (PNG) for a release name.
    public func image(for system: SystemID, name: String) async throws -> Data {
        try await fetch(BoxArt.imageURL(for: system, name: name))
    }
}

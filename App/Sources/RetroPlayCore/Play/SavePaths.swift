// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Sandbox layout under Documents so Files → On My iPhone → RetroPlay shows a clear tree.
/// Games, Saves, States, Cheats — never invented ROM paths. App-internal data (library.json,
/// Covers, Cache) lives in Application Support so it is not exposed in Files.
public struct SavePaths: Sendable {
    public let documentsURL: URL
    /// Application Support root for app-internal files.
    public let supportURL: URL

    /// With no `documentsURL`, both roots are the real sandbox folders. An injected
    /// `documentsURL` (tests) without `supportURL` keeps app data in a hidden folder inside it,
    /// so each temporary root stays self-contained.
    public init(fileManager: FileManager = .default, documentsURL: URL? = nil, supportURL: URL? = nil) {
        let documents = documentsURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documentsURL = documents
        if let supportURL {
            self.supportURL = supportURL
        } else if documentsURL != nil {
            self.supportURL = documents.appendingPathComponent(".AppSupport", isDirectory: true)
        } else {
            self.supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
    }

    /// Imported ROMs / ISOs.
    public var gamesDirectory: URL {
        documentsURL.appendingPathComponent("Games", isDirectory: true)
    }

    /// Legacy name; same folder as `gamesDirectory` after migration.
    public var romsDirectory: URL { gamesDirectory }

    /// SRAM / in-game saves (and per-core memstick trees such as `Saves/psp-memstick`).
    public var savesDirectory: URL {
        documentsURL.appendingPathComponent("Saves", isDirectory: true)
    }

    /// Quick / slot save states.
    public var statesDirectory: URL {
        documentsURL.appendingPathComponent("States", isDirectory: true)
    }

    /// Transferable cheat files the cores already produce.
    public var cheatsDirectory: URL {
        documentsURL.appendingPathComponent("Cheats", isDirectory: true)
    }

    /// BIOS files the player adds (Files → RetroPlay → BIOS), e.g. a PS1 `scph5501.bin`.
    /// The libretro cores read it as their system directory.
    public var biosDirectory: URL {
        documentsURL.appendingPathComponent("BIOS", isDirectory: true)
    }

    public var n64SavesDirectory: URL {
        savesDirectory.appendingPathComponent("n64", isDirectory: true)
    }

    /// PPSSPP memory stick root. Must not be named "PSP" in any case: PPSSPP then treats it
    /// as the PSP folder itself (`GetSysDirectory`), while `ms0:` still mounts it as the root,
    /// so SAVEDATA dialogs create folders in one place and write files in the other.
    public var pspMemstickDirectory: URL {
        savesDirectory.appendingPathComponent("psp-memstick", isDirectory: true)
    }

    /// In-game PSP save dialogs write here (`PSP/SAVEDATA`). Host quick-states stay under `States/`.
    public var pspSavedataDirectory: URL {
        pspMemstickDirectory
            .appendingPathComponent("PSP", isDirectory: true)
            .appendingPathComponent("SAVEDATA", isDirectory: true)
    }

    public var pspGameDirectory: URL {
        pspMemstickDirectory
            .appendingPathComponent("PSP", isDirectory: true)
            .appendingPathComponent("GAME", isDirectory: true)
    }

    public var pspSystemDirectory: URL {
        pspMemstickDirectory
            .appendingPathComponent("PSP", isDirectory: true)
            .appendingPathComponent("SYSTEM", isDirectory: true)
    }

    public var cacheDirectory: URL {
        supportURL.appendingPathComponent("Cache", isDirectory: true)
    }

    /// Extracted cover art (`<game UUID>.jpg`).
    public var coversDirectory: URL {
        supportURL.appendingPathComponent("Covers", isDirectory: true)
    }

    public var libraryFileURL: URL {
        supportURL.appendingPathComponent("library.json", isDirectory: false)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for url in [
            gamesDirectory,
            savesDirectory,
            statesDirectory,
            cheatsDirectory,
            n64SavesDirectory,
            biosDirectory,
            pspMemstickDirectory,
            pspSavedataDirectory,
            pspGameDirectory,
            pspSystemDirectory,
            cacheDirectory
        ] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Rejects `..`, absolute paths, and empty components. Used to keep sandbox writes inside Documents.
    public static func sanitizedRelativePath(_ relativePath: String) -> String? {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        for component in components {
            if component.isEmpty || component == "." || component == ".." {
                return nil
            }
        }
        return components.joined(separator: "/")
    }

    /// Leaf filenames only — no path separators or parent hops.
    public static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        guard !name.contains("/"), !name.contains("\\") else { return false }
        return sanitizedRelativePath(name) != nil
    }

    public func gamesURL(forRelativePath relativePath: String) -> URL? {
        guard let safe = Self.sanitizedRelativePath(relativePath) else { return nil }
        return resolvedURL(under: gamesDirectory, relativePath: safe)
    }

    /// Resolves a library ROM the same way as `LibraryStore.absoluteURL` — never escapes `Games/`.
    public func gameROMURL(forRelativePath relativePath: String) -> URL {
        gamesURL(forRelativePath: relativePath)
            ?? gamesDirectory.appendingPathComponent(
                (relativePath as NSString).lastPathComponent,
                isDirectory: false
            )
    }

    /// ROM path relative to `gamesDirectory`, or `lastPathComponent` when outside the sandbox tree.
    public func relativeROMPath(fromAbsoluteROMURL url: URL) -> String {
        let gamesPath = gamesDirectory.standardizedFileURL.path
        let romPath = url.standardizedFileURL.path
        let prefix = gamesPath + "/"
        if romPath.hasPrefix(prefix) {
            return String(romPath.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    /// SRAM file mirroring the ROM relative path under Saves/ with `.sav`.
    public func sramURL(forRelativeROMPath relativePath: String) -> URL {
        let base = (relativePath as NSString).deletingPathExtension
        let savRelative = base + ".sav"
        if let url = resolvedURL(under: savesDirectory, relativePath: savRelative) {
            return url
        }
        let leaf = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return savesDirectory.appendingPathComponent(leaf + ".sav")
    }

    /// Mupen64Plus-Next combined `.srm` under `Saves/n64/`, basename-matched to the ROM.
    public func n64SRAMURL(forRelativeROMPath relativePath: String) -> URL {
        let leaf = (relativePath as NSString).lastPathComponent
        let base = (leaf as NSString).deletingPathExtension
        return n64SavesDirectory.appendingPathComponent(base + ".srm")
    }

    public func batterySaveURL(for game: LibraryGame) -> URL {
        SaveFormat.of(game.systemID).destination(for: game, paths: self)
    }

    /// Set when saves were imported for a game from the library: its next launch boots fresh
    /// instead of resuming the quick save, which still holds the old save in memory and would
    /// write it back over the imported one.
    public func freshBootMarkerURL(for gameID: UUID) -> URL {
        supportURL
            .appendingPathComponent("FreshBoot", isDirectory: true)
            .appendingPathComponent(gameID.uuidString, isDirectory: false)
    }

    public func stateURL(forRelativeROMPath relativePath: String, slot: Int) -> URL {
        let base = (relativePath as NSString).deletingPathExtension
        let stateRelative = "\(base).slot\(slot).state"
        if let url = resolvedURL(under: statesDirectory, relativePath: stateRelative) {
            return url
        }
        let leaf = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return statesDirectory.appendingPathComponent("\(leaf).slot\(slot).state")
    }

    private func resolvedURL(under base: URL, relativePath: String) -> URL? {
        guard let safe = Self.sanitizedRelativePath(relativePath) else { return nil }
        return safe.split(separator: "/").reduce(base) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
    }

    /// Older builds kept library.json, Covers/ and Cache/ in Documents, where Files showed them.
    /// Moves them to Application Support once; never overwrites data already there.
    public func migrateAppDataOutOfDocuments(fileManager: FileManager = .default) throws {
        guard supportURL.standardizedFileURL != documentsURL.standardizedFileURL else { return }
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let legacyLibrary = documentsURL.appendingPathComponent("library.json", isDirectory: false)
        if fileManager.fileExists(atPath: legacyLibrary.path),
           !fileManager.fileExists(atPath: libraryFileURL.path) {
            try fileManager.moveItem(at: legacyLibrary, to: libraryFileURL)
        }
        try mergeDirectory(
            documentsURL.appendingPathComponent("Covers", isDirectory: true),
            into: coversDirectory,
            fileManager: fileManager
        )
        let legacyCache = documentsURL.appendingPathComponent("Cache", isDirectory: true)
        try mergeDirectory(legacyCache, into: cacheDirectory, fileManager: fileManager)
        // Anything left collided with an existing cache entry; caches are disposable.
        if fileManager.fileExists(atPath: legacyCache.path) {
            try? fileManager.removeItem(at: legacyCache)
        }
    }

    /// Move Documents/ROMs, old Saves UUID states, N64Saves, and PPSSPP into the current layout.
    public func migrateLegacyLayout(fileManager: FileManager = .default) throws {
        let legacyROMs = documentsURL.appendingPathComponent("ROMs", isDirectory: true)
        try mergeDirectory(legacyROMs, into: gamesDirectory, fileManager: fileManager)

        try migrateLegacyQuickStates(fileManager: fileManager)

        try migrateROMAdjacentSaves(fileManager: fileManager)

        let legacyN64 = documentsURL.appendingPathComponent("N64Saves", isDirectory: true)
        try mergeDirectory(legacyN64, into: n64SavesDirectory, fileManager: fileManager)

        let legacyPSP = documentsURL.appendingPathComponent("PPSSPP", isDirectory: true)
        try mergeDirectory(legacyPSP, into: pspMemstickDirectory, fileManager: fileManager)

        // The memory stick used to be Saves/psp. Saves there sat in PSP/SAVEDATA (game side)
        // or SAVEDATA (PPSSPP side, see pspMemstickDirectory). Move both; leave the caches.
        let oldMemstick = savesDirectory.appendingPathComponent("psp", isDirectory: true)
        for oldSavedata in [
            oldMemstick.appendingPathComponent("PSP", isDirectory: true)
                .appendingPathComponent("SAVEDATA", isDirectory: true),
            oldMemstick.appendingPathComponent("SAVEDATA", isDirectory: true),
        ] {
            try mergeDirectory(oldSavedata, into: pspSavedataDirectory, fileManager: fileManager)
        }

        let legacyCache = documentsURL.appendingPathComponent("PPSSPPCache", isDirectory: true)
        try mergeDirectory(
            legacyCache,
            into: cacheDirectory.appendingPathComponent("psp", isDirectory: true),
            fileManager: fileManager
        )
    }

    /// Older builds kept GBA battery saves next to the ROM (`Games/<rom>.sav`); drivers now
    /// read `Saves/<rom>.sav`. Moves each one unless the new location already has a save.
    private func migrateROMAdjacentSaves(fileManager: FileManager) throws {
        guard let walker = fileManager.enumerator(at: gamesDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        let gamesPath = gamesDirectory.standardizedFileURL.path + "/"
        for case let url as URL in walker where url.pathExtension.lowercased() == "sav" {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(gamesPath) else { continue }
            let dest = sramURL(forRelativeROMPath: String(path.dropFirst(gamesPath.count)))
            guard !fileManager.fileExists(atPath: dest.path) else { continue }
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: dest)
        }
    }

    private func migrateLegacyQuickStates(fileManager: FileManager) throws {
        for system in SystemID.allCases {
            let oldRoot = savesDirectory.appendingPathComponent(system.rawValue, isDirectory: true)
            guard fileManager.fileExists(atPath: oldRoot.path) else { continue }
            let children = try fileManager.contentsOfDirectory(
                at: oldRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir, UUID(uuidString: child.lastPathComponent) != nil else { continue }
                let dest = statesDirectory
                    .appendingPathComponent(system.rawValue, isDirectory: true)
                    .appendingPathComponent(child.lastPathComponent, isDirectory: true)
                try fileManager.createDirectory(
                    at: dest.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: dest.path) {
                    try mergeDirectory(child, into: dest, fileManager: fileManager)
                } else {
                    try fileManager.moveItem(at: child, to: dest)
                }
            }
            if let leftover = try? fileManager.contentsOfDirectory(at: oldRoot, includingPropertiesForKeys: nil),
               leftover.isEmpty {
                try fileManager.removeItem(at: oldRoot)
            }
        }
    }

    private func mergeDirectory(_ source: URL, into destination: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )
        for item in items {
            let dest = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                continue
            }
            try fileManager.moveItem(at: item, to: dest)
        }
        if let leftover = try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil),
           leftover.isEmpty {
            try fileManager.removeItem(at: source)
        }
    }
}

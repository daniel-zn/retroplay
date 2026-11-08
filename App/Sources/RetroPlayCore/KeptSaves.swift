// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A save imported for a game that isn't in the library: a battery file waiting in
/// `KeptSaves/<system>/` (app data), or a PSP SAVEDATA slot no library game owns.
public struct KeptSave: Identifiable, Sendable, Equatable {
    public let url: URL
    public let system: SystemID
    /// The file or slot folder name, as kept.
    public let name: String
    /// What to call it: the file name without its extension, or the PSP save's own title.
    public let title: String
    public let modified: Date?
    public let bytes: Int
    public var id: String { url.path }
}

/// Saves kept for games not in the library yet. A battery save the library import can't match
/// to a game, but whose system is known (its folder or name says it), is kept under its own
/// name; when a game it names is added, it moves to the path that game's core boots from. PSP
/// slots need no move: PPSSPP finds them in SAVEDATA by product ID.
public enum KeptSaves {
    public static func directory(paths: SavePaths) -> URL {
        paths.supportURL.appendingPathComponent("KeptSaves", isDirectory: true)
    }

    /// Where a battery save for a game not in the library is kept.
    public static func url(system: SystemID, fileName: String, paths: SavePaths) -> URL {
        directory(paths: paths)
            .appendingPathComponent(system.rawValue, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Every kept save, PSP slots included (those no game in `games` owns), by title.
    public static func list(games: [LibraryGame], paths: SavePaths, fileManager: FileManager = .default) -> [KeptSave] {
        var saves: [KeptSave] = []
        for system in SystemID.allCases where SaveFormat.of(system).layout == .batteryFile {
            for file in files(system: system, paths: paths, fileManager: fileManager) {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                saves.append(KeptSave(
                    url: file,
                    system: system,
                    name: file.lastPathComponent,
                    title: file.deletingPathExtension().lastPathComponent,
                    modified: values?.contentModificationDate,
                    bytes: values?.fileSize ?? 0
                ))
            }
        }
        if let inventory = try? PSPSavedataInventory.scan(games: games, paths: paths, fileManager: fileManager) {
            let unowned = Set(inventory.unownedProductIDs)
            for slot in inventory.slots where unowned.contains(slot.folderName) {
                let contents = (try? fileManager.contentsOfDirectory(
                    at: slot.directoryURL,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                let values = contents.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) }
                let sfo = contents.first { $0.lastPathComponent.uppercased() == "PARAM.SFO" }
                let title = sfo.flatMap { try? Data(contentsOf: $0) }.flatMap(PSPParamSFO.title(from:))
                saves.append(KeptSave(
                    url: slot.directoryURL,
                    system: .psp,
                    name: slot.directoryURL.lastPathComponent,
                    title: title ?? slot.directoryURL.lastPathComponent,
                    modified: values.compactMap(\.contentModificationDate).max(),
                    bytes: values.compactMap(\.fileSize).reduce(0, +)
                ))
            }
        }
        return saves.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
        }
    }

    public static func delete(_ save: KeptSave, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: save.url)
    }

    /// Moves each kept battery save that names one of `added` (and no other game in `library`)
    /// to where that game's core reads it, unless the game has a save there already. The newest
    /// of several wins; the others stay kept. Returns the games that got a save.
    @discardableResult
    public static func attach(
        to added: [LibraryGame],
        library: [LibraryGame],
        paths: SavePaths,
        fileManager: FileManager = .default
    ) -> [LibraryGame] {
        let addedIDs = Set(added.map(\.id))
        var attached: [LibraryGame] = []
        for system in Set(added.map(\.systemID)) where SaveFormat.of(system).layout == .batteryFile {
            let index = TitleIndex(games: library.filter { $0.systemID == system })
            var byGame: [UUID: (game: LibraryGame, files: [URL])] = [:]
            for file in files(system: system, paths: paths, fileManager: fileManager) {
                let base = file.deletingPathExtension().lastPathComponent
                let ext = file.pathExtension.lowercased()
                guard let matches = TitleIndex.Tier.allCases.lazy
                    .map({ index.games(named: base, tier: $0, saveExtension: ext) })
                    .first(where: { !$0.isEmpty }),
                    matches.count == 1, let game = matches.first, addedIDs.contains(game.id)
                else { continue }
                byGame[game.id, default: (game, [])].files.append(file)
            }
            for (game, files) in byGame.values {
                let dest = SaveFormat.of(system).destination(for: game, paths: paths)
                guard !fileManager.fileExists(atPath: dest.path) else { continue }
                let newest = files.max { modified($0) < modified($1) }!
                do {
                    try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fileManager.moveItem(at: newest, to: dest)
                    attached.append(game)
                } catch {
                    continue
                }
            }
        }
        return attached
    }

    private static func files(system: SystemID, paths: SavePaths, fileManager: FileManager) -> [URL] {
        let folder = directory(paths: paths).appendingPathComponent(system.rawValue, isDirectory: true)
        let children = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// The game's own in-game save (battery file or PSP SAVEDATA), for the pause menu.
public enum InGameSave {
    /// When the save the game boots with was last written; nil if it has none.
    public static func lastSaved(for game: LibraryGame, paths: SavePaths, fileManager: FileManager = .default) -> Date? {
        let format = SaveFormat.of(game.systemID)
        switch format.layout {
        case .batteryFile:
            let url = format.destination(for: game, paths: paths)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        case .pspSavedataFolders:
            guard let id = game.pspProductID,
                  let inventory = try? PSPSavedataInventory.scan(games: [game], paths: paths, fileManager: fileManager)
            else { return nil }
            let dates = inventory.slots
                .filter { SaveGameImporter.pspSaveFolder($0.folderName, belongsTo: id) }
                .flatMap { slot -> [Date] in
                    let files = (try? fileManager.contentsOfDirectory(
                        at: slot.directoryURL,
                        includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    return (files.isEmpty ? [slot.directoryURL] : files)
                        .map { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
                }
            return dates.max()
        }
    }
}

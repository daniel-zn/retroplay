// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct GameArtifactCleanupResult: Sendable, Equatable {
    public let retainedPSPSavedata: Bool
    public let retainedPSPSavedataReason: String?

    public static let complete = GameArtifactCleanupResult(
        retainedPSPSavedata: false,
        retainedPSPSavedataReason: nil
    )
}

/// One or more cleanup steps failed. Every other step still ran.
public struct GameArtifactCleanupError: LocalizedError, Sendable {
    public let failures: [String]

    public var errorDescription: String? {
        "Some files for this game could not be removed: " + failures.joined(separator: "; ")
    }
}

/// Deletes sandbox files that belong to one library game. Never touches files outside Documents,
/// and never files another library row still uses (same ROM base name or PSP product ID).
public enum GameArtifactCleanup: Sendable {
    /// Best-effort: a missing ROM counts as already removed, each step runs even if an earlier
    /// one failed, and failures are thrown together at the end.
    @discardableResult
    public static func removeArtifacts(
        for game: LibraryGame,
        paths: SavePaths,
        otherGames: [LibraryGame] = [],
        fileManager: FileManager = .default
    ) throws -> GameArtifactCleanupResult {
        var failures: [String] = []
        func attempt(_ label: String, _ body: () throws -> Void) {
            do {
                try body()
            } catch {
                failures.append("\(label): \(error.localizedDescription)")
            }
        }

        let others = otherGames.filter { $0.id != game.id }
        let romURL = paths.gameROMURL(forRelativePath: game.relativePath)
        // A PS1 .cue sheet's track files sit next to it (in the game's own folder).
        let tracks = romURL.pathExtension.lowercased() == "cue"
            ? CueSheet.referencedFiles(at: romURL)
            : []
        attempt("game file") {
            try removeItemIfPresent(romURL, fileManager: fileManager)
        }
        for track in tracks {
            attempt("disc track") {
                try removeItemIfPresent(
                    romURL.deletingLastPathComponent().appendingPathComponent(track),
                    fileManager: fileManager
                )
            }
        }
        let folder = romURL.deletingLastPathComponent()
        if folder.standardizedFileURL != paths.gamesDirectory.standardizedFileURL,
           (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            attempt("game folder") { try fileManager.removeItem(at: folder) }
        }

        // Saves, states and cheats are keyed by ROM base name. Rows imported by older builds
        // can share one (Game.gba + Game.nds); keep those files for the surviving row.
        let base = baseName(of: game.relativePath)
        let baseShared = others.contains { baseName(of: $0.relativePath) == base }
        if !baseShared {
            switch game.systemID {
            case .n64:
                attempt("battery save") {
                    try removeItemIfPresent(
                        paths.n64SRAMURL(forRelativeROMPath: game.relativePath),
                        fileManager: fileManager
                    )
                }
            case .gba, .nds, .nes, .snes, .genesis, .atari7800, .ps1:
                attempt("battery save") {
                    try removeItemIfPresent(
                        paths.sramURL(forRelativeROMPath: game.relativePath),
                        fileManager: fileManager
                    )
                }
            case .psp:
                break
            }
            for slot in 0...9 {
                attempt("save state \(slot)") {
                    try removeItemIfPresent(
                        paths.stateURL(forRelativeROMPath: game.relativePath, slot: slot),
                        fileManager: fileManager
                    )
                }
            }

            var sidecarDirectories = [paths.savesDirectory, paths.statesDirectory, paths.cheatsDirectory]
            if game.systemID == .n64 {
                sidecarDirectories.append(paths.n64SavesDirectory)
            }
            for directory in sidecarDirectories {
                attempt(directory.lastPathComponent) {
                    try removeMatchingSidecars(
                        namedLike: game.relativePath,
                        in: directory,
                        fileManager: fileManager
                    )
                }
            }
        }

        let quickDir = SaveStateStore.quickSaveDirectory(
            system: game.systemID,
            gameID: game.id,
            paths: paths
        )
        attempt("quick saves") {
            try removeItemIfPresent(quickDir, fileManager: fileManager)
        }

        // Pre-migration quick-state folder.
        let legacyQuick = paths.savesDirectory
            .appendingPathComponent(game.systemID.rawValue, isDirectory: true)
            .appendingPathComponent(game.id.uuidString, isDirectory: true)
        attempt("legacy quick saves") {
            try removeItemIfPresent(legacyQuick, fileManager: fileManager)
        }

        let covers = CoverArtStore(fileManager: fileManager, paths: paths)
        attempt("cover") {
            try covers.removeCover(forGameID: game.id)
        }

        var cleanupResult = GameArtifactCleanupResult.complete
        if game.systemID == .psp {
            attempt("PSP save data") {
                cleanupResult = try removePSPSavedata(
                    for: game,
                    others: others,
                    paths: paths,
                    fileManager: fileManager
                )
            }
        }

        if !failures.isEmpty {
            throw GameArtifactCleanupError(failures: failures)
        }
        return cleanupResult
    }

    private static func removePSPSavedata(
        for game: LibraryGame,
        others: [LibraryGame],
        paths: SavePaths,
        fileManager: FileManager
    ) throws -> GameArtifactCleanupResult {
        guard let productID = game.pspProductID else {
            return GameArtifactCleanupResult(
                retainedPSPSavedata: true,
                retainedPSPSavedataReason:
                    "PSP product ID is unknown for this library entry; shared SAVEDATA was left intact."
            )
        }
        guard SaveGameImporter.isValidPSPGameID(productID) else {
            return GameArtifactCleanupResult(
                retainedPSPSavedata: true,
                retainedPSPSavedataReason:
                    "PSP product ID “\(productID)” is invalid; shared SAVEDATA was left intact."
            )
        }
        if others.contains(where: { $0.systemID == .psp && $0.pspProductID == productID }) {
            return GameArtifactCleanupResult(
                retainedPSPSavedata: true,
                retainedPSPSavedataReason:
                    "Another game in your library uses product ID \(productID); its SAVEDATA was left intact."
            )
        }
        let root = paths.pspSavedataDirectory
        guard fileManager.fileExists(atPath: root.path) else { return .complete }
        // Games name their folders <productID><save name> (e.g. ULUS10041DATA00).
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var failures: [String] = []
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir,
                  SaveGameImporter.pspSaveFolder(child.lastPathComponent, belongsTo: productID)
            else { continue }
            do {
                try fileManager.removeItem(at: child)
            } catch {
                failures.append("\(child.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw GameArtifactCleanupError(failures: failures)
        }
        return .complete
    }

    /// Leaf file name without its extension, case-folded (Game.gba and game.NDS collide).
    static func baseName(of relativePath: String) -> String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
    }

    private static func removeMatchingSidecars(
        namedLike relativeROMPath: String,
        in directory: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let base = ((relativeROMPath as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !base.isEmpty else { return }
        let items = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in items {
            let name = (item.lastPathComponent as NSString).deletingPathExtension
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue }
            if name == base {
                try removeItemIfPresent(item, fileManager: fileManager)
            }
        }
    }

    private static func removeItemIfPresent(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

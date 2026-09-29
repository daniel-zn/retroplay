// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Sandbox save-state paths. Never ship states or ROMs in git.
public enum SaveStateStore: Sendable {
    public static let maximumSaveCount = 5

    public struct Entry: Identifiable, Equatable, Sendable {
        /// Zero is the current quick save; higher slots are progressively older.
        public let slot: Int
        public let url: URL
        public let modifiedAt: Date?

        public var id: Int { slot }

        public init(slot: Int, url: URL, modifiedAt: Date?) {
            self.slot = slot
            self.url = url
            self.modifiedAt = modifiedAt
        }
    }

    /// `Documents/States/<system>/<gameUUID>/quick.state`
    public static func quickSaveDirectory(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths()
    ) -> URL {
        paths.statesDirectory
            .appendingPathComponent(system.rawValue, isDirectory: true)
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
    }

    public static func quickSaveURL(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default,
        createDirectory: Bool = true
    ) throws -> URL {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        if createDirectory {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return saveURL(slot: 0, directory: dir)
    }

    /// A temporary destination lets the core finish writing before the previous saves rotate.
    public static func stagingSaveURL(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("quick.pending.state", isDirectory: false)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    /// Promotes a completed staged save and keeps the current save plus four older saves.
    public static func commitStagedQuickSave(
        _ stagedURL: URL,
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: stagedURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        for destinationSlot in stride(from: maximumSaveCount - 1, through: 1, by: -1) {
            let source = saveURL(slot: destinationSlot - 1, directory: dir)
            let destination = saveURL(slot: destinationSlot, directory: dir)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
        try fileManager.moveItem(at: stagedURL, to: saveURL(slot: 0, directory: dir))
    }

    /// Existing saves in deterministic newest-to-oldest slot order. Missing slots are skipped.
    public static func entries(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> [Entry] {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        return (0..<maximumSaveCount).compactMap { slot in
            entryIfPresent(slot: slot, directory: dir, fileManager: fileManager)
        }
    }

    /// Committed slots plus a staged `quick.pending.state` when it is newer than slot 0.
    public static func resolvedEntries(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> [Entry] {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        var committed = entries(system: system, gameID: gameID, paths: paths, fileManager: fileManager)
        guard let pending = pendingEntryIfPreferred(directory: dir, fileManager: fileManager) else {
            return committed
        }
        committed.removeAll { $0.slot == 0 }
        return [pending] + committed
    }

    public static func quickSaveExists(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> Bool {
        let url = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        return fileManager.fileExists(atPath: saveURL(slot: 0, directory: url).path)
    }

    /// Newest available quick-save entry (slot 0 when present, otherwise the next oldest slot).
    public static func newestEntry(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> Entry? {
        resolvedEntries(system: system, gameID: gameID, paths: paths, fileManager: fileManager).first
    }

    public static func anySaveExists(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> Bool {
        newestEntry(system: system, gameID: gameID, paths: paths, fileManager: fileManager) != nil
    }

    public static func removeAllSaves(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) throws {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    /// Drops an in-flight `quick.pending.state` after a failed quick-save so a partial write
    /// cannot shadow a good committed slot 0 on the next load/auto-resume.
    public static func discardPendingQuickSave(
        system: SystemID,
        gameID: UUID,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) {
        let dir = quickSaveDirectory(system: system, gameID: gameID, paths: paths)
        let pendingURL = pendingSaveURL(directory: dir)
        try? fileManager.removeItem(at: pendingURL)
    }

    private static func saveURL(slot: Int, directory: URL) -> URL {
        precondition((0..<maximumSaveCount).contains(slot))
        let filename = slot == 0 ? "quick.state" : "quick-\(slot).state"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func pendingSaveURL(directory: URL) -> URL {
        directory.appendingPathComponent("quick.pending.state", isDirectory: false)
    }

    private static func entryIfPresent(
        slot: Int,
        directory: URL,
        fileManager: FileManager
    ) -> Entry? {
        let url = saveURL(slot: slot, directory: directory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        return Entry(slot: slot, url: url, modifiedAt: modifiedAt)
    }

    private static func pendingEntryIfPreferred(
        directory: URL,
        fileManager: FileManager
    ) -> Entry? {
        let pendingURL = pendingSaveURL(directory: directory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: pendingURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }

        let pendingModifiedAt = try? pendingURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let committedURL = saveURL(slot: 0, directory: directory)
        guard fileManager.fileExists(atPath: committedURL.path) else {
            return Entry(slot: 0, url: pendingURL, modifiedAt: pendingModifiedAt)
        }
        let committedModifiedAt = try? committedURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        guard (pendingModifiedAt ?? .distantPast) > (committedModifiedAt ?? .distantPast) else {
            return nil
        }
        return Entry(slot: 0, url: pendingURL, modifiedAt: pendingModifiedAt)
    }
}

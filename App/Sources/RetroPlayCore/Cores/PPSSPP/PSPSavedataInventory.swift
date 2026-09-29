// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One `PSP/SAVEDATA/<FOLDER>/` slot on the virtual memstick. Games name their folders with
/// their product ID, usually plus a save name (`ULUS10041DATA00`); a bare ID also occurs.
public struct PSPSavedataSlot: Sendable, Equatable, Identifiable {
    /// Product ID of the library game that owns the folder; the folder's leading product ID
    /// (or the whole folder name) when no library game owns it.
    public let productID: String
    /// On-disk folder name, upper-cased (e.g. `ULUS10041DATA00`).
    public let folderName: String
    public let directoryURL: URL

    public var id: String { folderName }

    public init(productID: String, directoryURL: URL, folderName: String? = nil) {
        self.productID = productID
        self.directoryURL = directoryURL
        self.folderName = folderName ?? directoryURL.lastPathComponent.uppercased()
    }
}

/// Ownership mapping between library PSP titles and memstick SAVEDATA folders.
public struct PSPSavedataInventory: Sendable, Equatable {
    public let slots: [PSPSavedataSlot]
    /// SAVEDATA folder names no library game's `pspProductID` owns.
    public let unownedProductIDs: [String]
    /// Library PSP games with a known product ID but no on-disk SAVEDATA folder.
    public let gamesMissingSavedata: [UUID]

    public init(
        slots: [PSPSavedataSlot],
        unownedProductIDs: [String],
        gamesMissingSavedata: [UUID]
    ) {
        self.slots = slots
        self.unownedProductIDs = unownedProductIDs
        self.gamesMissingSavedata = gamesMissingSavedata
    }

    public static func scan(
        games: [LibraryGame],
        paths: SavePaths,
        fileManager: FileManager = .default
    ) throws -> PSPSavedataInventory {
        let savedataRoot = paths.pspSavedataDirectory
        guard fileManager.fileExists(atPath: savedataRoot.path) else {
            let knownGames = games.filter { $0.systemID == .psp && $0.pspProductID != nil }
            return PSPSavedataInventory(
                slots: [],
                unownedProductIDs: [],
                gamesMissingSavedata: knownGames.map(\.id)
            )
        }

        let children = try fileManager.contentsOfDirectory(
            at: savedataRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let ownedIDs = Set(
            games.compactMap { game -> String? in
                guard game.systemID == .psp, let id = game.pspProductID else { return nil }
                return id
            }
        )

        var slots: [PSPSavedataSlot] = []
        var unowned: [String] = []
        var idsWithSavedata = Set<String>()
        for child in children {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let folderName = child.lastPathComponent.uppercased()
            guard SaveGameImporter.isValidPSPSaveFolderName(folderName) else { continue }
            let owners = ownedIDs.filter { SaveGameImporter.pspSaveFolder(folderName, belongsTo: $0) }
            idsWithSavedata.formUnion(owners)
            let owner = owners.sorted().first
            if owner == nil { unowned.append(folderName) }
            slots.append(PSPSavedataSlot(
                productID: owner ?? Self.leadingProductID(of: folderName),
                directoryURL: child,
                folderName: folderName
            ))
        }
        slots.sort { $0.folderName < $1.folderName }
        unowned.sort()

        let missing = games.compactMap { game -> UUID? in
            guard game.systemID == .psp, let id = game.pspProductID else { return nil }
            return idsWithSavedata.contains(id) ? nil : game.id
        }

        return PSPSavedataInventory(
            slots: slots,
            unownedProductIDs: unowned,
            gamesMissingSavedata: missing
        )
    }

    /// `ULUS10041DATA00` → `ULUS10041`; a bare or non-standard ID comes back unchanged.
    static func leadingProductID(of folderName: String) -> String {
        if SaveGameImporter.isValidPSPGameID(folderName) { return folderName }
        let prefix = String(folderName.prefix(9))
        return SaveGameImporter.pspSaveFolder(folderName, belongsTo: prefix) ? prefix : folderName
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SaveGameImportError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case saveStateNotImportable
    case compressedRetroArchSave
    case basenameMismatch(expected: String, got: String)
    case invalidSize(system: SystemID, bytes: Int)
    case missingPSPMetadata
    case invalidPSPGameID(String)
    case pspTitleMismatch(expected: String, imported: String)
    case destinationExists(URL)
    case securityScopedAccessFailed
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let detail):
            return "Unsupported save format: \(detail)"
        case .saveStateNotImportable:
            return "Save states (.state) are not portable between emulators. Import a battery save (.sav/.srm) or PSP SAVEDATA folder instead."
        case .compressedRetroArchSave:
            return "This save looks RetroArch rzip-compressed. Decompress it in RetroArch (Settings → Saving) and export the raw .srm/.sav before importing."
        case .basenameMismatch(let expected, let got):
            return "Save name “\(got)” does not match this game (“\(expected)”). Rename the file to match the imported ROM basename."
        case .invalidSize(let system, let bytes):
            return "Invalid \(system.displayName) save size (\(bytes) bytes)."
        case .missingPSPMetadata:
            return "PSP save folders must include PARAM.SFO."
        case .invalidPSPGameID(let id):
            return "“\(id)” is not a valid PSP SAVEDATA folder name."
        case .pspTitleMismatch(let expected, let imported):
            return "Save folder “\(imported)” does not match this game's product ID (\(expected))."
        case .destinationExists(let url):
            return "A save already exists at \(url.lastPathComponent). Confirm overwrite to replace it."
        case .securityScopedAccessFailed:
            return "Could not read the selected file (security-scoped access failed)."
        case .copyFailed(let detail):
            return "Could not copy save data: \(detail)"
        }
    }
}

/// Result of validating a user-picked battery save before copying into the sandbox.
public struct SaveGameImportPlan: Sendable, Equatable {
    public let sourceDescription: String
    public let destinationURL: URL
    public let replacesExisting: Bool
    public let warning: String?

    public init(
        sourceDescription: String,
        destinationURL: URL,
        replacesExisting: Bool,
        warning: String? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.destinationURL = destinationURL
        self.replacesExisting = replacesExisting
        self.warning = warning
    }
}

/// Imports RetroArch / standalone battery saves into RetroPlay's per-core layout.
/// Quick-states under `States/` are intentionally out of scope.
public struct SaveGameImporter: Sendable {
    public init() {}

    private static let pspProductIDPattern = try! NSRegularExpression(
        pattern: #"^(UC|UL|NP|EP|EB|HB|NPUH|NPEG|NPHH)[A-Z0-9]{4,8}(\d{2})?$"#,
        options: []
    )

    /// Retail product IDs: four letters + five digits (ULUS10041).
    private static let standardPSPProductIDPattern = try! NSRegularExpression(
        pattern: #"^[A-Z]{4}[0-9]{5}$"#,
        options: []
    )

    /// Real SAVEDATA folders append a save name to the product ID (ULUS10041DATA00,
    /// UCUS98648PROFILE00). The PSP caps the whole name at 32 characters.
    private static let pspSaveFolderPattern = try! NSRegularExpression(
        pattern: #"^[A-Z]{4}[0-9]{5}[A-Z0-9_]{1,23}$"#,
        options: []
    )

    public func planImport(
        from sourceURL: URL,
        for game: LibraryGame,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) throws -> SaveGameImportPlan {
        let ext = sourceURL.pathExtension.lowercased()
        if SaveImportContentTypes.isSaveStateExtension(ext) {
            throw SaveGameImportError.saveStateNotImportable
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw SaveGameImportError.unsupportedFormat("File not found.")
        }

        if isDir.boolValue {
            guard game.systemID == .psp else {
                throw SaveGameImportError.unsupportedFormat(
                    "Battery save folders are only for PSP SAVEDATA imports. Pick a .sav/.srm file for \(game.systemID.displayName)."
                )
            }
            return try planPSPFolderImport(
                from: sourceURL,
                for: game,
                paths: paths,
                fileManager: fileManager
            )
        }

        guard SaveImportContentTypes.isBatteryExtension(ext) else {
            throw SaveGameImportError.unsupportedFormat(".\(ext) is not a supported battery-save extension.")
        }
        if game.systemID == .psp {
            throw SaveGameImportError.unsupportedFormat(
                "PSP in-game saves are folders (SAVEDATA/<GAMEID>/ with PARAM.SFO). Pick that folder, not a loose file."
            )
        }

        let romBase = Self.romBasename(for: game)
        let saveBase = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        if saveBase != romBase {
            throw SaveGameImportError.basenameMismatch(expected: romBase, got: saveBase)
        }

        let data = try withReadableSource(sourceURL, fileManager: fileManager) {
            try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        }
        try Self.validateBatteryFile(extension: ext, size: data.count, header: data.prefix(8), system: game.systemID)
        let dest = SaveFormat.of(game.systemID).destination(for: game, paths: paths)
        return plan(dest: dest, source: sourceURL.lastPathComponent, fileManager: fileManager)
    }

    /// Checks a battery file against its system's `SaveFormat`: the extension, the size, and
    /// that it isn't a RetroArch rzip-compressed save. `header` is at least the file's first
    /// five bytes (or all of it when shorter).
    public static func validateBatteryFile(
        extension rawExt: String,
        size: Int,
        header: Data,
        system: SystemID
    ) throws {
        let ext = rawExt.lowercased()
        if SaveImportContentTypes.isSaveStateExtension(ext) {
            throw SaveGameImportError.saveStateNotImportable
        }
        if looksRzipCompressed(header) {
            throw SaveGameImportError.compressedRetroArchSave
        }
        let format = SaveFormat.of(system)
        guard format.layout == .batteryFile else {
            throw SaveGameImportError.unsupportedFormat(
                "\(system.displayName) saves are folders, not single files."
            )
        }
        if let reason = format.unusableExtensions[ext] {
            throw SaveGameImportError.unsupportedFormat(reason)
        }
        guard format.extensions.contains(ext) else {
            throw SaveGameImportError.unsupportedFormat(".\(ext) is not a \(system.displayName) save.")
        }
        guard format.acceptsSize(size) else {
            throw SaveGameImportError.invalidSize(system: system, bytes: size)
        }
    }

    public func commitImport(
        plan: SaveGameImportPlan,
        from sourceURL: URL,
        overwrite: Bool,
        fileManager: FileManager = .default
    ) throws {
        if plan.replacesExisting, !overwrite {
            throw SaveGameImportError.destinationExists(plan.destinationURL)
        }

        try withReadableSource(sourceURL, fileManager: fileManager) {
            var isDir: ObjCBool = false
            let isDirectory = fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) && isDir.boolValue

            try fileManager.createDirectory(
                at: plan.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let stagingURL = plan.destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".import-\(UUID().uuidString)-\(plan.destinationURL.lastPathComponent)")

            do {
                if isDirectory {
                    try copyDirectory(from: sourceURL, to: stagingURL, fileManager: fileManager)
                } else {
                    try fileManager.copyItem(at: sourceURL, to: stagingURL)
                }
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw SaveGameImportError.copyFailed(error.localizedDescription)
            }

            if fileManager.fileExists(atPath: plan.destinationURL.path) {
                if isDirectory {
                    try atomicReplaceDirectory(
                        at: plan.destinationURL,
                        with: stagingURL,
                        fileManager: fileManager
                    )
                } else {
                    _ = try fileManager.replaceItemAt(
                        plan.destinationURL,
                        withItemAt: stagingURL,
                        backupItemName: ".import-backup-\(UUID().uuidString)",
                        options: []
                    )
                }
            } else {
                try fileManager.moveItem(at: stagingURL, to: plan.destinationURL)
            }
        }
    }

    // MARK: - PSP SAVEDATA folder

    func planPSPFolderImport(
        from folderURL: URL,
        for game: LibraryGame,
        paths: SavePaths,
        fileManager: FileManager
    ) throws -> SaveGameImportPlan {
        let folderName = folderURL.lastPathComponent.uppercased()
        guard SavePaths.isSafeFileName(folderName) else {
            throw SaveGameImportError.unsupportedFormat(
                "PSP SAVEDATA folder names cannot contain path separators."
            )
        }
        if folderName.uppercased() == "SAVEDATA" {
            throw SaveGameImportError.unsupportedFormat(
                "Pick a game folder inside SAVEDATA (for example ULUS12345), not the SAVEDATA directory itself."
            )
        }

        let paramURL = folderURL.appendingPathComponent("PARAM.SFO")
        guard fileManager.fileExists(atPath: paramURL.path) else {
            if Self.isValidPSPSaveFolderName(folderName) {
                throw SaveGameImportError.missingPSPMetadata
            }
            throw SaveGameImportError.unsupportedFormat(
                "Folder is missing PARAM.SFO. Import a PSP SAVEDATA slot folder from RetroArch (saves/PPSSPP/PSP/SAVEDATA/<ID>/)."
            )
        }

        guard Self.isValidPSPSaveFolderName(folderName) else {
            throw SaveGameImportError.invalidPSPGameID(folderName)
        }

        if let expectedID = game.pspProductID, !Self.pspSaveFolder(folderName, belongsTo: expectedID) {
            throw SaveGameImportError.pspTitleMismatch(expected: expectedID, imported: folderName)
        }

        let dest = paths.pspSavedataDirectory.appendingPathComponent(folderName, isDirectory: true)
        return plan(dest: dest, source: folderName, fileManager: fileManager)
    }

    // MARK: - Validation helpers

    public static func looksRzipCompressed(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = String(data: data.prefix(min(5, data.count)), encoding: .ascii) ?? ""
        return prefix.hasPrefix("#RZIP") || prefix.hasPrefix("RZIP")
    }

    public static func isValidPSPGameID(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return pspProductIDPattern.firstMatch(in: name, options: [], range: range) != nil
    }

    /// A bare product ID or a product ID followed by a save name.
    public static func isValidPSPSaveFolderName(_ name: String) -> Bool {
        isValidPSPGameID(name) || matches(pspSaveFolderPattern, name)
    }

    /// True when a SAVEDATA folder was written by the game with this product ID: an exact
    /// match, or (for standard nine-character IDs only) the ID followed by a save name.
    public static func pspSaveFolder(_ folderName: String, belongsTo productID: String) -> Bool {
        let folder = folderName.uppercased()
        let id = productID.uppercased()
        if folder == id { return true }
        guard matches(standardPSPProductIDPattern, id), folder.hasPrefix(id) else { return false }
        return matches(pspSaveFolderPattern, folder)
    }

    private static func matches(_ pattern: NSRegularExpression, _ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return pattern.firstMatch(in: name, options: [], range: range) != nil
    }

    static func romBasename(for game: LibraryGame) -> String {
        let leaf = (game.relativePath as NSString).lastPathComponent
        return (leaf as NSString).deletingPathExtension
    }

    func plan(
        dest: URL,
        source: String,
        fileManager: FileManager,
        warning: String? = nil
    ) -> SaveGameImportPlan {
        SaveGameImportPlan(
            sourceDescription: source,
            destinationURL: dest,
            replacesExisting: fileManager.fileExists(atPath: dest.path),
            warning: warning
        )
    }

    private func withReadableSource<T>(
        _ sourceURL: URL,
        fileManager: FileManager,
        _ body: () throws -> T
    ) throws -> T {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        if !accessed, !fileManager.isReadableFile(atPath: sourceURL.path) {
            throw SaveGameImportError.securityScopedAccessFailed
        }
        return try body()
    }

    private func atomicReplaceDirectory(
        at destination: URL,
        with stagingURL: URL,
        fileManager: FileManager
    ) throws {
        let backupURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".import-backup-\(UUID().uuidString)-\(destination.lastPathComponent)")
        try fileManager.moveItem(at: destination, to: backupURL)
        do {
            try fileManager.moveItem(at: stagingURL, to: destination)
        } catch {
            try? fileManager.moveItem(at: backupURL, to: destination)
            throw error
        }
        try? fileManager.removeItem(at: backupURL)
    }

    private func copyDirectory(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        for item in items {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destItem.path) {
                try fileManager.removeItem(at: destItem)
            }
            try fileManager.copyItem(at: item, to: destItem)
        }
    }
}

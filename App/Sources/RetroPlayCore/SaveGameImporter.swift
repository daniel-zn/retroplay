// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SaveGameImportError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case saveStateNotImportable
    case compressedRetroArchSave
    case basenameMismatch(expected: String, got: String)
    case invalidSize(system: SystemID, bytes: Int)
    case missingPSPMetadata
    /// A slot every listing showed as empty whose PARAM.SFO couldn't be opened by name either.
    case pspSlotListedEmpty(String)
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
        case .pspSlotListedEmpty(let name):
            return "PSP save folders must include PARAM.SFO. iOS listed “\(name)” as empty and its PARAM.SFO couldn't be opened by name. Copy the folder to On My iPhone in Files and import it from there."
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
    /// What the copy must still be once staged, checked again right before it replaces
    /// anything (the source may have changed since the plan).
    public let check: StagedCheck?

    public enum StagedCheck: Sendable, Equatable {
        case batteryFile(system: SystemID, extension: String, lenient: Bool)
        case pspFolder
    }

    public init(
        sourceDescription: String,
        destinationURL: URL,
        replacesExisting: Bool,
        warning: String? = nil,
        check: StagedCheck? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.destinationURL = destinationURL
        self.replacesExisting = replacesExisting
        self.warning = warning
        self.check = check
    }
}

/// Imports RetroArch / standalone battery saves into RetroPlay's per-core layout.
/// Quick-states under `States/` are intentionally out of scope.
public struct SaveGameImporter: Sendable {
    public init() {}

    /// Bounds on a PSP save folder's contents (real ones hold a handful of files, a few MiB).
    public static let pspFolderMaxEntries = 256
    public static let pspFolderMaxDepth = 4
    public static let pspFolderMaxBytes = 128 << 20

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
        // Save names games really use: ULUS10560System, UCUS98632-GAMEDAT, UCUS98731_GameData0
        // (checked upper-cased).
        pattern: #"^[A-Z]{4}[0-9]{5}[A-Z0-9_\-]{1,23}$"#,
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
        // The player picked this file for this game: take what the import always took.
        try Self.validateBatteryFile(extension: ext, size: data.count, header: data.prefix(8), system: game.systemID, lenient: true)
        let dest = SaveFormat.of(game.systemID).destination(for: game, paths: paths)
        return plan(
            dest: dest,
            source: sourceURL.lastPathComponent,
            fileManager: fileManager,
            check: .batteryFile(system: game.systemID, extension: ext, lenient: true)
        )
    }

    /// Checks a battery file against its system's `SaveFormat`: the extension, the size, and
    /// that it isn't a RetroArch rzip-compressed save. `header` is at least the file's first
    /// five bytes (or all of it when shorter). `lenient`: the in-game import's wider rules
    /// (`SaveFormat.lenientExtensions`), for a file the player picked for one game.
    public static func validateBatteryFile(
        extension rawExt: String,
        size: Int,
        header: Data,
        system: SystemID,
        lenient: Bool = false
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
        guard (lenient ? format.lenientExtensions : format.extensions).contains(ext) else {
            throw SaveGameImportError.unsupportedFormat(".\(ext) is not a \(system.displayName) save.")
        }
        guard lenient ? format.acceptsLeniently(extension: ext, size: size) : format.acceptsSize(size) else {
            throw SaveGameImportError.invalidSize(system: system, bytes: size)
        }
    }

    /// Copies the source next to the destination, checks the copy (`plan.check`), runs
    /// `beforeInstall` (a throw there stops the import with nothing replaced), then swaps the
    /// copy in. `swap` exchanges two folders (injectable for tests).
    public func commitImport(
        plan: SaveGameImportPlan,
        from sourceURL: URL,
        overwrite: Bool,
        fileManager: FileManager = .default,
        beforeInstall: () throws -> Void = {},
        swap: (URL, URL) throws -> Void = SaveGameImporter.swapDirectory,
        cancellation: ImportCancellation = ImportCancellation()
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

            let parent = plan.destinationURL.deletingLastPathComponent()
            Self.removeLeftoverStaging(in: parent, fileManager: fileManager)
            let stagingURL = parent
                .appendingPathComponent("\(Self.stagingPrefix)\(UUID().uuidString)-\(plan.destinationURL.lastPathComponent)")

            do {
                if isDirectory {
                    // Folder by folder and file by file, each coordinated, within the PSP caps.
                    try Self.walkPSPSlot(sourceURL, copyingTo: stagingURL, fileManager: fileManager, cancellation: cancellation)
                } else {
                    // Coordinated, so a file in iCloud Drive or on a share is downloaded first; a
                    // file that changed since the plan (grown, emptied, now a link) isn't copied.
                    try CoordinatedRead.run(sourceURL, cancellation) { source in
                        if let check = plan.check {
                            try Self.validateStaged(source, check: check, fileManager: fileManager)
                        }
                        try fileManager.copyItem(at: source, to: stagingURL)
                    }
                }
            } catch let error as SaveGameImportError {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw SaveGameImportError.copyFailed(error.localizedDescription)
            }

            do {
                // The bytes about to be installed, not the ones the plan saw.
                if let check = plan.check {
                    try Self.validateStaged(stagingURL, check: check, fileManager: fileManager)
                }
                try beforeInstall()
                if isDirectory, !fileManager.fileExists(atPath: plan.destinationURL.path),
                   let other = Self.existingPSPSlot(for: plan.destinationURL, fileManager: fileManager) {
                    // A case-sensitive file system with the slot under another spelling (an
                    // earlier build upper-cased names): the new slot goes in under the game's
                    // spelling in one step; only then is the old spelling removed. Nothing in
                    // between can leave the old save lost.
                    try fileManager.moveItem(at: stagingURL, to: plan.destinationURL)
                    try? fileManager.removeItem(at: other)
                } else if fileManager.fileExists(atPath: plan.destinationURL.path) {
                    if isDirectory {
                        try swap(plan.destinationURL, stagingURL)
                        // The swap put the old folder at the staging path.
                        try? fileManager.removeItem(at: stagingURL)
                    } else {
                        _ = try fileManager.replaceItemAt(
                            plan.destinationURL,
                            withItemAt: stagingURL,
                            backupItemName: "\(Self.stagingPrefix)backup-\(UUID().uuidString)",
                            options: []
                        )
                    }
                } else {
                    try fileManager.moveItem(at: stagingURL, to: plan.destinationURL)
                }
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
        }
    }

    static let stagingPrefix = ".import-"

    /// Staged copies and swapped-out folders an interrupted import left behind. The real save
    /// next to them is whole either way (the swap and the replace are atomic).
    static func removeLeftoverStaging(in directory: URL, fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(stagingPrefix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Exchanges two folders in one step, so the destination is never missing, even if the app
    /// dies mid-import.
    public static func swapDirectory(at destination: URL, with staging: URL) throws {
        let result = staging.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renamex_np(from!, to!, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw SaveGameImportError.copyFailed(String(cString: strerror(errno)))
        }
    }

    static func validateStaged(_ url: URL, check: SaveGameImportPlan.StagedCheck, fileManager: FileManager) throws {
        switch check {
        case .batteryFile(let system, let ext, let lenient):
            // Read now from the file system: a URL's cached resource values can be from the scan.
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw SaveGameImportError.unsupportedFormat("Links and special files aren't imported; pick the save itself.")
            }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let header = try LibrarySaveImporter.readHeader(url)
            try validateBatteryFile(extension: ext, size: size, header: header, system: system, lenient: lenient)
        case .pspFolder:
            try validatePSPFolderContents(url, fileManager: fileManager)
        }
    }

    /// A PSP save folder holds plain files and folders only (no links that would point outside
    /// it once copied), at most `pspFolderMaxEntries` of them, `pspFolderMaxDepth` deep and
    /// `pspFolderMaxBytes` in all, with a PARAM.SFO at the top.
    public static func validatePSPFolderContents(
        _ folder: URL,
        fileManager: FileManager = .default,
        cancellation: ImportCancellation = ImportCancellation()
    ) throws {
        try walkPSPSlot(folder, copyingTo: nil, fileManager: fileManager, cancellation: cancellation)
    }

    private static let pspLinkError = SaveGameImportError.unsupportedFormat("Save folders with links in them aren't imported.")

    /// Checks a PSP slot with the same walk the library scan uses (each folder listed in its
    /// own coordinated read, each file copied in its own), copying it to `target` when given.
    /// Anything it can't read, or a limit passed, stops it with an error: a slot is copied
    /// whole or not at all.
    static func walkPSPSlot(
        _ slot: URL,
        copyingTo target: URL?,
        fileManager: FileManager,
        cancellation: ImportCancellation
    ) throws {
        let tooBig = SaveGameImportError.unsupportedFormat("Too big to be a PSP save folder.")
        if (try? slot.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { throw pspLinkError }
        if let target { try fileManager.createDirectory(at: target, withIntermediateDirectories: true) }
        var budget = FolderWalk.Budget(entries: pspFolderMaxEntries)
        var bytes = 0
        var hasParam = false
        let complete = try FolderWalk.run(
            slot,
            maxDepth: pspFolderMaxDepth,
            budget: &budget,
            fileManager: fileManager,
            cancellation: cancellation,
            unreadable: { folder, error in
                if let error = error as? SaveGameImportError { throw error }
                throw SaveGameImportError.copyFailed(
                    "\(folder.path.joined(separator: "/")) couldn't be read\(error.map { ": \($0.localizedDescription)" } ?? ".")"
                )
            }
        ) { folder, children in
            let here = target.map { folder.path.dropFirst().reduce($0) { $0.appendingPathComponent($1) } }
            var subfolders: [FolderWalk.Child] = []
            for child in children {
                try cancellation.check()
                if child.item.kind == .link { throw pspLinkError }
                if child.item.kind == .folder || child.item.kind == .package {
                    if let here {
                        try fileManager.createDirectory(at: here.appendingPathComponent(child.name), withIntermediateDirectories: true)
                    }
                    subfolders.append(child)
                    continue
                }
                bytes += child.item.size
                guard bytes <= pspFolderMaxBytes else { throw tooBig }
                if folder.path.count == 1, child.name.uppercased() == "PARAM.SFO" { hasParam = true }
                if let here {
                    let destination = here.appendingPathComponent(child.name)
                    try CoordinatedRead.run(child.url, cancellation) { try fileManager.copyItem(at: $0, to: destination) }
                }
            }
            return subfolders
        }
        guard complete else { throw tooBig }
        guard hasParam else { throw SaveGameImportError.missingPSPMetadata }
    }

    // MARK: - PSP SAVEDATA folder

    func planPSPFolderImport(
        from folderURL: URL,
        for game: LibraryGame?,
        paths: SavePaths,
        fileManager: FileManager
    ) throws -> SaveGameImportPlan {
        let originalName = folderURL.lastPathComponent
        let folderName = originalName.uppercased()
        guard SavePaths.isSafeFileName(originalName) else {
            throw SaveGameImportError.unsupportedFormat(
                "PSP SAVEDATA folder names cannot contain path separators."
            )
        }
        if folderName.uppercased() == "SAVEDATA" {
            throw SaveGameImportError.unsupportedFormat(
                "Pick a game folder inside SAVEDATA (for example ULUS12345), not the SAVEDATA directory itself."
            )
        }

        guard Self.isValidPSPSaveFolderName(folderName) else {
            throw SaveGameImportError.invalidPSPGameID(folderName)
        }

        if let expectedID = game?.pspProductID, !Self.pspSaveFolder(folderName, belongsTo: expectedID) {
            throw SaveGameImportError.pspTitleMismatch(expected: expectedID, imported: folderName)
        }

        try Self.validatePSPFolderContents(folderURL, fileManager: fileManager)

        let installName = Self.pspInstallName(originalName)
        let dest = paths.pspSavedataDirectory.appendingPathComponent(installName, isDirectory: true)
        return SaveGameImportPlan(
            sourceDescription: installName,
            destinationURL: dest,
            replacesExisting: Self.existingPSPSlot(for: dest, fileManager: fileManager) != nil,
            check: .pspFolder
        )
    }

    /// The name the game itself uses: PPSSPP compares save folder names case-sensitively when
    /// it lists them (SavedataParam), so ULUS10560System must stay ULUS10560System. Only a
    /// name that came back all lower-case (copied through a file system that folded it) is
    /// upper-cased again, as PSP product IDs and most save names are.
    static func pspInstallName(_ name: String) -> String {
        name == name.lowercased() ? name.uppercased() : name
    }

    /// The slot already on the memory stick for `destination`, matching its name in any case
    /// (an earlier build upper-cased names; iOS is case-sensitive, so it'd be a second folder).
    public static func existingPSPSlot(for destination: URL, fileManager: FileManager = .default) -> URL? {
        let parent = destination.deletingLastPathComponent()
        let wanted = destination.lastPathComponent.uppercased()
        let names = (try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? []
        if names.contains(destination.lastPathComponent) { return destination }
        return names.first { $0.uppercased() == wanted }.map { parent.appendingPathComponent($0, isDirectory: true) }
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
        warning: String? = nil,
        check: SaveGameImportPlan.StagedCheck? = nil
    ) -> SaveGameImportPlan {
        SaveGameImportPlan(
            sourceDescription: source,
            destinationURL: dest,
            replacesExisting: fileManager.fileExists(atPath: dest.path),
            warning: warning,
            check: check
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
}

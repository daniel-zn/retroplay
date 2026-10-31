// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Library-level save import: the player picks save files and folders (a RetroArch `saves/`
// tree, another app's export, a PSP `SAVEDATA` folder); the scanner finds what looks like a
// save, the planner matches each one to a library game and validates it with the same rules
// as the in-game import (`SaveFormat`, `SaveGameImporter`), and the commit writes each save
// atomically. Nothing is guessed: ambiguous and unmatched files are reported with a reason.

/// Bounds for one scan, so a huge folder can't hang the app.
public struct SaveScanLimits: Sendable, Equatable {
    /// Folder levels below a picked folder that are looked into.
    public var maxDepth: Int
    /// Files and folders looked at across the whole pick.
    public var maxEntries: Int
    /// Saves collected before the scan stops.
    public var maxCandidates: Int
    /// Larger files aren't saves (the biggest, a DS flash save, is 32 MiB).
    public var maxFileBytes: Int

    public init(maxDepth: Int = 12, maxEntries: Int = 20_000, maxCandidates: Int = 2_000, maxFileBytes: Int = 64 << 20) {
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
        self.maxCandidates = maxCandidates
        self.maxFileBytes = maxFileBytes
    }
}

/// Something the scanner found that may be a save.
public struct SaveImportCandidate: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case file(extension: String, size: Int)
        case pspFolder(name: String)
    }

    public let url: URL
    /// Path from the picked item, for the summary (`saves/mGBA/Zelda.srm`).
    public let displayPath: String
    public let kind: Kind
    /// Systems the folders around it name (RetroArch's `saves/mGBA/`, `Mupen64Plus-Next/`…).
    public let folderHints: Set<SystemID>
    public let modified: Date?
}

/// A file or folder that won't be imported, and why.
public struct SkippedSave: Error, Sendable, Equatable, Hashable, Identifiable {
    public let name: String
    public let reason: String
    public var id: String { name + "\u{0}" + reason }

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct SaveScanResult: Sendable, Equatable {
    public var candidates: [SaveImportCandidate] = []
    public var skipped: [SkippedSave] = []
    /// Files that are plainly not saves (pictures, ROMs, notes), counted but not listed.
    public var ignoredFiles = 0
    /// The scan stopped at a limit; some saves may not have been looked at.
    public var truncated = false
}

/// One save ready to write.
public struct SaveImportItem: Sendable, Equatable, Identifiable {
    public let game: LibraryGame
    public let sourceURL: URL
    public let sourceName: String
    public let plan: SaveGameImportPlan
    /// Every library entry that reads this save: the game, or for PSP each copy of the title
    /// (an ISO and a CSO share the memory stick folder).
    public let gameIDs: [UUID]
    public var id: String { plan.destinationURL.path }
    public var replacesExisting: Bool { plan.replacesExisting }

    public init(game: LibraryGame, sourceURL: URL, sourceName: String, plan: SaveGameImportPlan, gameIDs: [UUID]? = nil) {
        self.game = game
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.plan = plan
        self.gameIDs = gameIDs ?? [game.id]
    }
}

/// What a pick would import, shown before anything is written.
public struct SaveImportBatch: Sendable, Equatable {
    public var items: [SaveImportItem] = []
    public var skipped: [SkippedSave] = []
    public var ignoredFiles = 0
    public var truncated = false

    public init(items: [SaveImportItem] = [], skipped: [SkippedSave] = [], ignoredFiles: Int = 0, truncated: Bool = false) {
        self.items = items
        self.skipped = skipped
        self.ignoredFiles = ignoredFiles
        self.truncated = truncated
    }

    public var gameCount: Int { Set(items.map(\.game.id)).count }
    public var replacements: [SaveImportItem] { items.filter(\.replacesExisting) }
    public var newSaves: [SaveImportItem] { items.filter { !$0.replacesExisting } }
}

public struct SaveImportOutcome: Sendable, Equatable {
    public var imported: [SaveImportItem] = []
    /// Existing saves left as they were (the player chose to keep them).
    public var kept: [SaveImportItem] = []
    public var failed: [SkippedSave] = []
}

/// Where a library save import is. Games can't start until it's idle again (a running core
/// would write its old save over the imported one), and nothing is written while a game is open.
public enum SaveImportPhase: Sendable, Equatable {
    case idle
    case scanning
    case reviewing
    case committing

    public var allowsLaunchingGames: Bool { self == .idle }

    public static func mayWrite(gameOpen: Bool) -> Bool { !gameOpen }
}

// MARK: - Scanner

public enum SaveFolderScanner {
    private static let archiveExtensions: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz"]
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]
    private static let linkReason = "Links aren't imported; pick the file or folder itself."

    /// Walks the picked files and folders. Doesn't read file contents (sizes and names only),
    /// so it stays quick on big trees; the planner reads what it needs.
    public static func scan(
        _ urls: [URL],
        limits: SaveScanLimits = SaveScanLimits(),
        fileManager: FileManager = .default
    ) -> SaveScanResult {
        var result = SaveScanResult()
        var entries = 0
        for root in urls {
            guard !result.truncated else { break }
            // Picked items count against the limits like anything found inside a folder.
            if entries >= limits.maxEntries || result.candidates.count >= limits.maxCandidates {
                result.truncated = true
                break
            }
            let values = try? root.resourceValues(forKeys: Set(resourceKeys))
            if values?.isSymbolicLink == true {
                entries += 1
                result.skipped.append(SkippedSave(name: root.lastPathComponent, reason: linkReason))
            } else if values?.isDirectory == true {
                walk(root, limits: limits, entries: &entries, result: &result, fileManager: fileManager)
            } else {
                entries += 1
                classifyFile(root, values: values, displayPath: root.lastPathComponent, hintPath: [], limits: limits, result: &result)
            }
        }
        return result
    }

    private static func walk(
        _ root: URL,
        limits: SaveScanLimits,
        entries: inout Int,
        result: inout SaveScanResult,
        fileManager: FileManager
    ) {
        let rootName = root.lastPathComponent
        // The picked folder may itself be a PSP save (SAVEDATA/ULUS10041DATA00).
        if let kind = pspFolderKind(root, fileManager: fileManager) {
            entries += 1
            addPSPFolder(root, kind: kind, displayPath: rootName, result: &result)
            return
        }
        guard let walker = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            // Hidden files are skipped by hand: iCloud placeholders (".Name.sav.icloud") are
            // worth naming.
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        let rootComponents = root.standardizedFileURL.pathComponents
        while let next = walker.nextObject() {
            guard let url = next as? URL else { continue }
            entries += 1
            if entries > limits.maxEntries || result.candidates.count >= limits.maxCandidates {
                result.truncated = true
                return
            }
            let components = Array(url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count))
            let displayPath = ([rootName] + components).joined(separator: "/")
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = values?.isDirectory == true

            // A link could point anywhere (outside the pick, or nowhere once copied).
            if values?.isSymbolicLink == true {
                if !name.hasPrefix(".") {
                    result.skipped.append(SkippedSave(name: displayPath, reason: linkReason))
                }
                continue
            }

            if name.hasPrefix(".") {
                if isDirectory {
                    walker.skipDescendants()
                } else if name.hasSuffix(".icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    if SaveImportContentTypes.isBatteryExtension((real as NSString).pathExtension) {
                        result.skipped.append(SkippedSave(
                            name: ([rootName] + components.dropLast() + [real]).joined(separator: "/"),
                            reason: "Not downloaded from iCloud yet. Open it in Files once, then import again."
                        ))
                    }
                }
                continue
            }

            if isDirectory {
                if let kind = pspFolderKind(url, fileManager: fileManager) {
                    addPSPFolder(url, kind: kind, displayPath: displayPath, result: &result)
                    walker.skipDescendants()
                } else if walker.level >= limits.maxDepth {
                    walker.skipDescendants()
                    result.truncated = true
                }
                continue
            }
            // Folder names around the file, the picked folder's own name included.
            let hintPath = [rootName] + components.dropLast()
            classifyFile(url, values: values, displayPath: displayPath, hintPath: hintPath, limits: limits, result: &result)
        }
    }

    private enum PSPFolderKind {
        case save
        case missingParam
    }

    /// A PSP SAVEDATA slot: a product-ID folder name (in any case: copies through other file
    /// systems can come back lower-cased) with a PARAM.SFO inside. An upper-case folder named
    /// like one without PARAM.SFO is reported rather than ignored. Its contents are checked
    /// (bounded) when it's planned, not walked here.
    private static func pspFolderKind(_ url: URL, fileManager: FileManager) -> PSPFolderKind? {
        let name = url.lastPathComponent
        guard SaveGameImporter.isValidPSPSaveFolderName(name.uppercased()) else { return nil }
        if SaveGameImporter.paramSFO(in: url, fileManager: fileManager) != nil { return .save }
        return name == name.uppercased() ? .missingParam : nil
    }

    private static func addPSPFolder(
        _ url: URL,
        kind: PSPFolderKind,
        displayPath: String,
        result: inout SaveScanResult
    ) {
        switch kind {
        case .save:
            let modified = try? SaveGameImporter.paramSFO(in: url)?
                .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            result.candidates.append(SaveImportCandidate(
                url: url,
                displayPath: displayPath,
                kind: .pspFolder(name: url.lastPathComponent),
                folderHints: [.psp],
                modified: modified
            ))
        case .missingParam:
            result.skipped.append(SkippedSave(
                name: displayPath,
                reason: SaveGameImportError.missingPSPMetadata.localizedDescription
            ))
        }
    }

    private static func classifyFile(
        _ url: URL,
        values: URLResourceValues?,
        displayPath: String,
        hintPath: [String],
        limits: SaveScanLimits,
        result: inout SaveScanResult
    ) {
        let ext = url.pathExtension.lowercased()
        // "Game.state.auto": the extension alone says "auto".
        if SaveImportContentTypes.isSaveStateExtension(ext) {
            result.skipped.append(SkippedSave(
                name: displayPath,
                reason: "Save states only work in the emulator that made them; import the battery save (.sav/.srm) instead."
            ))
            return
        }
        if archiveExtensions.contains(ext) {
            result.skipped.append(SkippedSave(name: displayPath, reason: "Archives aren't opened; unzip it in Files first."))
            return
        }
        guard SaveImportContentTypes.isBatteryExtension(ext) else {
            result.ignoredFiles += 1
            return
        }
        let size = values?.fileSize ?? 0
        guard size <= limits.maxFileBytes else {
            result.skipped.append(SkippedSave(name: displayPath, reason: "Too large to be a save."))
            return
        }
        guard result.candidates.count < limits.maxCandidates else {
            result.truncated = true
            return
        }
        result.candidates.append(SaveImportCandidate(
            url: url,
            displayPath: displayPath,
            kind: .file(extension: ext, size: size),
            folderHints: hints(for: hintPath),
            modified: values?.contentModificationDate
        ))
    }

    static func hints(for folderNames: [String]) -> Set<SystemID> {
        var systems = Set<SystemID>()
        for folder in folderNames {
            let name = folder.lowercased()
            for format in SaveFormat.all.values where format.folderHints.contains(name) {
                systems.insert(format.system)
            }
        }
        return systems
    }
}

// MARK: - Matching and planning

public struct LibrarySaveImporter: Sendable {
    private let importer = SaveGameImporter()

    public init() {}

    /// Matches every candidate to one library game and validates it. Reads only the first bytes
    /// of matched files (and whole files only to compare against an existing save).
    public func plan(
        _ scan: SaveScanResult,
        games: [LibraryGame],
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> SaveImportBatch {
        var batch = SaveImportBatch(skipped: scan.skipped, ignoredFiles: scan.ignoredFiles, truncated: scan.truncated)
        let index = TitleIndex(games: games.filter { SaveFormat.of($0.systemID).layout == .batteryFile })
        let pspGames = games
            .filter { $0.systemID == .psp && $0.pspProductID != nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        var planned: [(item: SaveImportItem, modified: Date?)] = []
        for candidate in scan.candidates {
            let outcome: Result<SaveImportItem, SkippedSave>
            switch candidate.kind {
            case .file(let ext, let size):
                outcome = planFile(candidate, ext: ext, size: size, index: index, paths: paths, fileManager: fileManager)
            case .pspFolder(let name):
                outcome = planPSPFolder(candidate, name: name, games: pspGames, paths: paths, fileManager: fileManager)
            }
            switch outcome {
            case .success(let item): planned.append((item, candidate.modified))
            case .failure(let skipped): batch.skipped.append(skipped)
            }
        }

        // Several copies of one game's save (two exports, or saves/ and a backup): the newest wins.
        var byDestination: [String: [(item: SaveImportItem, modified: Date?)]] = [:]
        for entry in planned {
            byDestination[entry.item.id, default: []].append(entry)
        }
        for entry in planned {
            guard let group = byDestination[entry.item.id], group.first?.item == entry.item else { continue }
            let winner = group.enumerated().max { lhs, rhs in
                let l = lhs.element.modified ?? .distantPast
                let r = rhs.element.modified ?? .distantPast
                // Same date: keep the first one found.
                return l == r ? lhs.offset > rhs.offset : l < r
            }!.element.item
            for other in group where other.item != winner {
                batch.skipped.append(SkippedSave(
                    name: other.item.sourceName,
                    reason: "Another copy of \(winner.game.displayName)'s save is newer (\(winner.sourceName))."
                ))
            }
            if winner.replacesExisting, Self.sameContents(winner.sourceURL, winner.plan.destinationURL, fileManager: fileManager) {
                batch.skipped.append(SkippedSave(name: winner.sourceName, reason: "\(winner.game.displayName) already has this save."))
                continue
            }
            batch.items.append(winner)
        }
        batch.items.sort {
            let order = $0.game.displayName.localizedStandardCompare($1.game.displayName)
            return order == .orderedSame ? $0.sourceName < $1.sourceName : order == .orderedAscending
        }
        batch.skipped.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return batch
    }

    private func planFile(
        _ candidate: SaveImportCandidate,
        ext: String,
        size: Int,
        index: TitleIndex,
        paths: SavePaths,
        fileManager: FileManager
    ) -> Result<SaveImportItem, SkippedSave> {
        let name = candidate.displayPath
        let base = (candidate.url.lastPathComponent as NSString).deletingPathExtension
        if TitleIndex.memoryCardExtensions.contains(ext), base.range(of: #"_2$"#, options: .regularExpression) != nil {
            return .failure(SkippedSave(
                name: name,
                reason: "This is memory card 2. RetroPlay uses card 1 only; import the _1 card."
            ))
        }
        // Systems the save's folder (saves/melonDS/) or name (Zelda.gba.sav) says it's for. A
        // match on any other system is refused, even when it's the only one.
        var hinted = candidate.folderHints
        let inner = (base as NSString).pathExtension.lowercased()
        if !inner.isEmpty {
            hinted.formUnion(SystemID.allCases.filter { $0.fileExtensions.contains(inner) })
        }
        var firstRejection: String?
        for tier in TitleIndex.Tier.allCases {
            let matches = index.games(named: base, tier: tier, saveExtension: ext)
            guard !matches.isEmpty else { continue }
            let fitting = matches.filter { SaveFormat.of($0.systemID).accepts(extension: ext, size: size) }
            guard !fitting.isEmpty else {
                if firstRejection == nil, let game = matches.first {
                    firstRejection = rejection(ext: ext, size: size, system: game.systemID)
                }
                continue
            }
            var choices = fitting
            if !hinted.isEmpty {
                choices = fitting.filter { hinted.contains($0.systemID) }
                guard !choices.isEmpty else {
                    let saysFor = hinted.map(Self.shortSystem).sorted().joined(separator: "/")
                    let names = fitting.prefix(3).map { "\($0.displayName) (\(Self.shortSystem($0.systemID)))" }
                    return .failure(SkippedSave(
                        name: name,
                        reason: "Its folder or name says \(saysFor), but it matches \(names.joined(separator: ", ")). Not imported."
                    ))
                }
            }
            guard choices.count == 1, let game = choices.first else {
                let names = choices.prefix(4).map { "\($0.displayName) (\(Self.shortSystem($0.systemID)))" }
                return .failure(SkippedSave(
                    name: name,
                    reason: "Fits more than one game: \(names.joined(separator: ", ")). Rename it to match one game's file."
                ))
            }
            let header: Data
            do {
                header = try Self.readHeader(candidate.url)
            } catch {
                return .failure(SkippedSave(name: name, reason: "Couldn't be read. Make sure it's downloaded."))
            }
            do {
                try SaveGameImporter.validateBatteryFile(extension: ext, size: size, header: header, system: game.systemID)
            } catch {
                return .failure(SkippedSave(name: name, reason: error.localizedDescription))
            }
            let dest = SaveFormat.of(game.systemID).destination(for: game, paths: paths)
            let plan = importer.plan(
                dest: dest,
                source: candidate.url.lastPathComponent,
                fileManager: fileManager,
                check: .batteryFile(system: game.systemID, extension: ext, lenient: false)
            )
            return .success(SaveImportItem(game: game, sourceURL: candidate.url, sourceName: name, plan: plan))
        }
        return .failure(SkippedSave(
            name: name,
            reason: firstRejection ?? "No game in your library has this name. Import the game first, or rename the save to match its file."
        ))
    }

    private func rejection(ext: String, size: Int, system: SystemID) -> String {
        do {
            try SaveGameImporter.validateBatteryFile(extension: ext, size: size, header: Data(), system: system)
            return "Not a \(system.displayName) save."
        } catch {
            return error.localizedDescription
        }
    }

    private func planPSPFolder(
        _ candidate: SaveImportCandidate,
        name: String,
        games: [LibraryGame],
        paths: SavePaths,
        fileManager: FileManager
    ) -> Result<SaveImportItem, SkippedSave> {
        // Every copy of a game shares the memory stick folder: the first owner names the row,
        // and all of them boot fresh.
        let owners = games.filter { SaveGameImporter.pspSaveFolder(name, belongsTo: $0.pspProductID!) }
        guard let game = owners.first else {
            let id = PSPSavedataInventory.leadingProductID(of: name.uppercased())
            return .failure(SkippedSave(
                name: candidate.displayPath,
                reason: "No PSP game in your library has product ID \(id). Import the game first."
            ))
        }
        do {
            let plan = try importer.planPSPFolderImport(from: candidate.url, for: game, paths: paths, fileManager: fileManager)
            return .success(SaveImportItem(
                game: game,
                sourceURL: candidate.url,
                sourceName: candidate.displayPath,
                plan: plan,
                gameIDs: owners.map(\.id)
            ))
        } catch {
            return .failure(SkippedSave(name: candidate.displayPath, reason: error.localizedDescription))
        }
    }

    /// Writes each save on its own (staged copy, checked again, then an atomic replace), so a
    /// failure leaves that game's old save whole and doesn't stop the others. Every game that
    /// reads the save is marked to boot fresh first (`FreshBoot`); if that fails, its save
    /// isn't touched. The caller makes sure no game is running.
    public func commit(
        _ batch: SaveImportBatch,
        replaceExisting: Bool,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> SaveImportOutcome {
        var outcome = SaveImportOutcome()
        for item in batch.items {
            // Re-checked now: the destination may have appeared since the summary was shown.
            let exists = fileManager.fileExists(atPath: item.plan.destinationURL.path)
            if exists, !replaceExisting {
                outcome.kept.append(item)
                continue
            }
            let plan = SaveGameImportPlan(
                sourceDescription: item.plan.sourceDescription,
                destinationURL: item.plan.destinationURL,
                replacesExisting: exists,
                warning: item.plan.warning,
                check: item.plan.check
            )
            do {
                for id in item.gameIDs {
                    try FreshBoot.mark(id, paths: paths, fileManager: fileManager)
                }
                try importer.commitImport(plan: plan, from: item.sourceURL, overwrite: replaceExisting, fileManager: fileManager)
                outcome.imported.append(item)
            } catch {
                outcome.failed.append(SkippedSave(name: item.sourceName, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    // MARK: Helpers

    static func readHeader(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 8) ?? Data()
    }

    static func sameContents(_ a: URL, _ b: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: b.path, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fileManager.contentsEqual(atPath: a.path, andPath: b.path)
    }

    static func shortSystem(_ system: SystemID) -> String {
        switch system {
        case .gba: return "GBA"
        case .n64: return "N64"
        case .nds: return "DS"
        case .psp: return "PSP"
        case .nes: return "NES"
        case .snes: return "SNES"
        case .genesis: return "Genesis"
        case .atari7800: return "7800"
        case .ps1: return "PS1"
        }
    }
}

// MARK: - Title matching

/// Library games by name, at three levels of strictness. A save matches at the strictest
/// level that finds any game, so "Zelda (USA).srm" picks "Zelda (USA).gba" over
/// "Zelda (Europe).gba", and only falls back to the tag-free title when no file name fits.
struct TitleIndex {
    enum Tier: CaseIterable {
        /// The ROM file name, as is.
        case exact
        /// Ignoring case.
        case caseInsensitive
        /// The title with region/revision tags, punctuation and accents dropped.
        case title
    }

    static let memoryCardExtensions: Set<String> = ["mcd", "mcr"]

    private var exact: [String: [LibraryGame]] = [:]
    private var folded: [String: [LibraryGame]] = [:]
    private var titles: [String: [LibraryGame]] = [:]

    init(games: [LibraryGame]) {
        for game in games {
            let base = SaveGameImporter.romBasename(for: game)
            exact[base, default: []].append(game)
            folded[base.lowercased(), default: []].append(game)
            let title = Self.normalizedTitle(base)
            if !title.isEmpty { titles[title, default: []].append(game) }
        }
    }

    func games(named saveBase: String, tier: Tier, saveExtension: String) -> [LibraryGame] {
        var bases = [saveBase]
        // "Zelda.gba.sav" (some apps keep the ROM extension).
        let inner = (saveBase as NSString).pathExtension.lowercased()
        if !inner.isEmpty, SystemID.allCases.contains(where: { $0.fileExtensions.contains(inner) }) {
            bases.append((saveBase as NSString).deletingPathExtension)
        }
        // DuckStation names per-game memory cards "<title>_1.mcd" (card 1). Only the bare
        // title is tried: "Crash_1" must not fall through to a game called "Crash 1".
        if Self.memoryCardExtensions.contains(saveExtension), let range = saveBase.range(of: #"_1$"#, options: .regularExpression) {
            bases = [String(saveBase[..<range.lowerBound])]
        }
        var seen = Set<UUID>()
        var found: [LibraryGame] = []
        for base in bases {
            let hits: [LibraryGame]
            switch tier {
            case .exact: hits = exact[base] ?? []
            case .caseInsensitive: hits = folded[base.lowercased()] ?? []
            case .title:
                let title = Self.normalizedTitle(base)
                hits = title.isEmpty ? [] : titles[title] ?? []
            }
            for game in hits where seen.insert(game.id).inserted {
                found.append(game)
            }
        }
        return found
    }

    /// "Legend of Zelda, The - A Link to the Past (USA) [!]" → "the legend of zelda a link to the past".
    static func normalizedTitle(_ name: String) -> String {
        var text = name.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        // No-Intro moves a leading article back ("Legend of Zelda, The - …").
        text = text.replacingOccurrences(
            of: #"^\s*([^,]+?),\s*(The|A|An)\b"#,
            with: "$2 $1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        text = text.replacingOccurrences(of: "&", with: " and ")
        return text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Fresh boot after a library import

/// A game whose save was replaced from the library must not auto-resume its quick save: the
/// state carries the old save in memory, and the core would write it back on exit. The marker
/// makes launches boot fresh until a quick save newer than the import exists (the one written
/// when that fresh session is left); a session that dies before then still boots fresh again.
public enum FreshBoot {
    public static func mark(_ gameID: UUID, paths: SavePaths, fileManager: FileManager = .default) throws {
        let url = paths.freshBootMarkerURL(for: gameID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written anew so its date is the import's.
        try Data().write(to: url, options: .atomic)
    }

    /// True while the game should boot without resuming. Clears the marker once a quick save
    /// newer than it exists.
    public static func isPending(
        _ gameID: UUID,
        system: SystemID,
        paths: SavePaths,
        fileManager: FileManager = .default
    ) -> Bool {
        let url = paths.freshBootMarkerURL(for: gameID)
        guard let marked = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return false
        }
        let newest = SaveStateStore.newestEntry(system: system, gameID: gameID, paths: paths, fileManager: fileManager)
        if let saved = newest?.modifiedAt, saved > marked {
            try? fileManager.removeItem(at: url)
            return false
        }
        return true
    }

    public static func clear(_ gameID: UUID, paths: SavePaths, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: paths.freshBootMarkerURL(for: gameID))
    }
}

// MARK: - Security-scoped access

/// Keeps every picked URL readable from the scan until the commit (or the summary closes);
/// files inside a picked folder are covered by the folder's access.
public final class SecurityScopedAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [URL]

    public init(_ urls: [URL]) {
        started = urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    public func stop() {
        lock.lock()
        let urls = started
        started = []
        lock.unlock()
        for url in urls { url.stopAccessingSecurityScopedResource() }
    }

    deinit { stop() }
}

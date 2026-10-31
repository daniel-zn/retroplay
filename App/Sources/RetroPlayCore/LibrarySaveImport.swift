// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

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
    /// The task was cancelled: the result is incomplete and shouldn't be shown.
    public var cancelled = false
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
    /// The destination, in its exact spelling (spellings of one PSP slot are settled before
    /// copies are compared; see `LibrarySaveImporter.plan`).
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

/// One library save import at a time. Each scan gets an id; the scan's completion, the commit
/// and the summary closing only act for the session still in progress, so a late completion
/// of an earlier one can't move the phase (and let a game start while another writes).
@MainActor
@Observable
public final class SaveImportSessions {
    public private(set) var phase = SaveImportPhase.idle
    private var current: UUID?

    public init() {}

    /// No new import (games or saves) while one is under way.
    public var allowsImporting: Bool { phase == .idle }
    public var allowsLaunchingGames: Bool { phase.allowsLaunchingGames }

    /// Starts a scan, or nil while another import is under way.
    public func beginScan() -> UUID? {
        guard phase == .idle else { return nil }
        let id = UUID()
        current = id
        phase = .scanning
        return id
    }

    /// The scan finished. True (now reviewing) only for the session in progress.
    public func scanFinished(_ id: UUID) -> Bool {
        guard current == id, phase == .scanning else { return false }
        phase = .reviewing
        return true
    }

    /// True (now committing) only for the session under review, with no game open.
    public func beginCommit(_ id: UUID, gameOpen: Bool) -> Bool {
        guard current == id, phase == .reviewing, SaveImportPhase.mayWrite(gameOpen: gameOpen) else { return false }
        phase = .committing
        return true
    }

    /// The summary was closed without importing. Ignored while that session writes.
    public func cancel(_ id: UUID) {
        guard phase != .committing else { return }
        end(id)
    }

    /// The session is over (nothing found, or written). Stale ids are ignored.
    public func end(_ id: UUID) {
        guard current == id else { return }
        current = nil
        phase = .idle
    }
}

// MARK: - Scanner

public enum SaveFolderScanner {
    private static let archiveExtensions: Set<String> = ["zip", "7z", "rar", "tar", "gz", "tgz"]
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]
    private static let linkReason = "Links aren't imported; pick the file or folder itself."
    static let otherSystemReason = "Not a save for a system RetroPlay plays."

    /// Walks the picked files and folders. Doesn't read file contents (sizes and names only),
    /// so it stays quick on big trees; the planner reads what it needs.
    ///
    /// Folders are walked breadth-first, each listed (one level) inside its own short
    /// coordinated read, as Apple recommends for File Provider locations (iCloud Drive, an SMB
    /// share): a provider fills each folder when it's asked for it, which one claim on the
    /// picked folder doesn't do. Cancelling the task stops a read still waiting.
    public static func scan(
        _ urls: [URL],
        limits: SaveScanLimits = SaveScanLimits(),
        fileManager: FileManager = .default
    ) -> SaveScanResult {
        var result = SaveScanResult()
        var entries = 0
        for root in urls {
            guard !result.truncated, !result.cancelled else { break }
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            // Picked items count against the limits like anything found inside a folder.
            if entries >= limits.maxEntries || result.candidates.count >= limits.maxCandidates {
                result.truncated = true
                break
            }
            let values: URLResourceValues
            do {
                values = try CoordinatedRead.run(root) { try $0.resourceValues(forKeys: Set(resourceKeys)) }
            } catch is CancellationError {
                result.cancelled = true
                break
            } catch {
                // Not known to be a file or a folder: say so rather than guess.
                entries += 1
                result.skipped.append(readError(root.lastPathComponent, error))
                continue
            }
            if values.isSymbolicLink == true {
                entries += 1
                result.skipped.append(SkippedSave(name: root.lastPathComponent, reason: linkReason))
            } else if values.isDirectory == true {
                walk(root, limits: limits, entries: &entries, result: &result, fileManager: fileManager)
            } else {
                entries += 1
                classifyFile(root, values: values, displayPath: root.lastPathComponent, folders: [], limits: limits, result: &result)
            }
        }
        return result
    }

    static func readError(_ name: String, _ error: Error?) -> SkippedSave {
        SkippedSave(name: name, reason: "Couldn't read it: \(error?.localizedDescription ?? "its contents can't be looked at").")
    }

    private struct Folder {
        let url: URL
        /// Names from the picked folder (included) down to this one.
        let path: [String]
    }

    private static func walk(
        _ root: URL,
        limits: SaveScanLimits,
        entries: inout Int,
        result: inout SaveScanResult,
        fileManager: FileManager
    ) {
        var queue = [Folder(url: root, path: [root.lastPathComponent])]
        var next = 0
        while next < queue.count {
            let folder = queue[next]
            next += 1
            if Task.isCancelled {
                result.cancelled = true
                return
            }
            let displayPath = folder.path.joined(separator: "/")
            // This folder only, under its own claim; the claim ends before anything is done
            // with the listing.
            let children: [(url: URL, values: URLResourceValues?)]
            do {
                children = try CoordinatedRead.run(folder.url) { url in
                    try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [])
                        .map { ($0, try? $0.resourceValues(forKeys: Set(resourceKeys))) }
                        .sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
                }
            } catch is CancellationError {
                result.cancelled = true
                return
            } catch {
                // Not downloaded, no permission: reported, and the walk goes on with the rest.
                result.skipped.append(readError(displayPath, error))
                continue
            }
            // Names it can list but nothing it can look at (no search permission): one error.
            if !children.isEmpty, children.allSatisfy({ $0.values == nil }) {
                result.skipped.append(readError(displayPath, nil))
                continue
            }
            if let decision = folderDecision(folder, children: children) {
                switch decision {
                case .pspSave(let modified):
                    result.candidates.append(SaveImportCandidate(
                        url: folder.url,
                        displayPath: displayPath,
                        kind: .pspFolder(name: folder.url.lastPathComponent),
                        folderHints: [.psp],
                        modified: modified
                    ))
                case .skip(let reason):
                    result.skipped.append(SkippedSave(name: displayPath, reason: reason))
                }
                continue
            }
            for child in children {
                entries += 1
                if entries > limits.maxEntries || result.candidates.count >= limits.maxCandidates {
                    result.truncated = true
                    return
                }
                let name = child.url.lastPathComponent
                let childPath = folder.path + [name]
                // A link could point anywhere (outside the pick, or nowhere once copied).
                if child.values?.isSymbolicLink == true {
                    if !name.hasPrefix(".") {
                        result.skipped.append(SkippedSave(name: childPath.joined(separator: "/"), reason: linkReason))
                    }
                    continue
                }
                let isDirectory = child.values?.isDirectory == true
                if name.hasPrefix(".") {
                    // Hidden folders are passed over; iCloud placeholders (".Name.sav.icloud")
                    // are worth naming.
                    if !isDirectory, name.hasSuffix(".icloud") {
                        let real = String(name.dropFirst().dropLast(".icloud".count))
                        if SaveImportContentTypes.isBatteryExtension((real as NSString).pathExtension) {
                            result.skipped.append(SkippedSave(
                                name: (folder.path + [real]).joined(separator: "/"),
                                reason: "Not downloaded from iCloud yet. Open it in Files once, then import again."
                            ))
                        }
                    }
                    continue
                }
                if isDirectory {
                    guard child.values?.isPackage != true else { continue }
                    if childPath.count - 1 >= limits.maxDepth {
                        result.truncated = true
                    } else {
                        queue.append(Folder(url: child.url, path: childPath))
                    }
                    continue
                }
                classifyFile(
                    child.url,
                    values: child.values,
                    displayPath: childPath.joined(separator: "/"),
                    folders: folder.path,
                    limits: limits,
                    result: &result
                )
            }
        }
    }

    private enum FolderDecision {
        case pspSave(modified: Date?)
        case skip(String)
    }

    /// Vita title IDs (PCSA00017) and Wii U account folders (80000001): only these names,
    /// with what's around them, say a folder isn't RetroPlay's. Names like "PC" don't.
    private static let vitaTitleID = try! NSRegularExpression(pattern: #"^PCS[A-Z][0-9]{5}$"#)
    private static let wiiUAccount = try! NSRegularExpression(pattern: #"^800000[0-9a-f]{2}$"#)

    private static func matches(_ pattern: NSRegularExpression, _ name: String) -> Bool {
        pattern.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)) != nil
    }

    /// What a folder is, from its own listing: a PSP save slot (a product ID and save name,
    /// in any case, with a PARAM.SFO), a folder to skip whole (a PSP-looking slot without
    /// PARAM.SFO, a PARAM.SFO under a name that isn't a save's, a Vita save with sce_sys, a
    /// Wii U account folder), or nil to look inside.
    private static func folderDecision(_ folder: Folder, children: [(url: URL, values: URLResourceValues?)]) -> FolderDecision? {
        let name = folder.url.lastPathComponent
        let param = children.first { $0.url.lastPathComponent.uppercased() == "PARAM.SFO" && $0.values?.isDirectory != true }
        let names = Set(children.map { $0.url.lastPathComponent.lowercased() })
        if matches(vitaTitleID, name), names.contains("sce_sys") {
            return .skip(otherSystemReason.replacingOccurrences(of: "a save", with: "saves"))
        }
        if matches(wiiUAccount, name) {
            return .skip(otherSystemReason.replacingOccurrences(of: "a save", with: "saves"))
        }
        if SaveGameImporter.isValidPSPSaveFolderName(name.uppercased()) {
            if let param { return .pspSave(modified: param.values?.contentModificationDate) }
            if name == name.uppercased() {
                return .skip(SaveGameImportError.missingPSPMetadata.localizedDescription)
            }
            return nil
        }
        if param != nil {
            return .skip("Has a PARAM.SFO, but “\(name)” isn't a PSP save folder name (a product ID like ULUS10041 and a save name).")
        }
        return nil
    }

    private static func classifyFile(
        _ url: URL,
        values: URLResourceValues?,
        displayPath: String,
        folders: [String],
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
        // Inside a Vita title or Wii U account folder: not a cartridge save, whatever its name.
        if folders.contains(where: { matches(vitaTitleID, $0) || matches(wiiUAccount, $0) }) {
            result.skipped.append(SkippedSave(name: displayPath, reason: otherSystemReason))
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
            folderHints: hints(for: folders),
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

        guard !scan.cancelled else { return SaveImportBatch() }
        var planned: [(item: SaveImportItem, modified: Date?)] = []
        for candidate in scan.candidates {
            if Task.isCancelled { return SaveImportBatch() }
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

        planned = settlePSPSpellings(planned, skipped: &batch.skipped)

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

    /// Spellings of one PSP slot (ULUS10560System, and ULUS10560SYSTEM from a build that
    /// upper-cased names) become one: the game's mixed-case spelling, whatever the dates, since
    /// PPSSPP only lists a save under the name the game asks for. Two different mixed-case
    /// spellings can't be told apart, so both are reported.
    private func settlePSPSpellings(
        _ planned: [(item: SaveImportItem, modified: Date?)],
        skipped: inout [SkippedSave]
    ) -> [(item: SaveImportItem, modified: Date?)] {
        var spellings: [String: Set<String>] = [:]
        for entry in planned where entry.item.plan.check == .pspFolder {
            let dest = entry.item.plan.destinationURL
            spellings[dest.path.uppercased(), default: []].insert(dest.lastPathComponent)
        }
        return planned.filter { entry in
            let dest = entry.item.plan.destinationURL
            guard entry.item.plan.check == .pspFolder,
                  let names = spellings[dest.path.uppercased()], names.count > 1 else { return true }
            let mixed = names.filter { $0 != $0.uppercased() }
            if mixed.count == 1, let chosen = mixed.first {
                if dest.lastPathComponent == chosen { return true }
                skipped.append(SkippedSave(
                    name: entry.item.sourceName,
                    reason: "The game names this save “\(chosen)”; that copy is imported."
                ))
                return false
            }
            skipped.append(SkippedSave(
                name: entry.item.sourceName,
                reason: "Spelled differently from another copy (\(names.sorted().joined(separator: ", "))). Keep only the one the game uses."
            ))
            return false
        }
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
        // Which systems it can be for, before any name is looked at: a ROM extension in the
        // name (Zelda.gba.sav) says so outright; otherwise the folder (saves/melonDS/) does. A
        // name and folder that disagree, or a match only on another system, are refused.
        let named = Set(SystemID.allCases.filter { system in
            let inner = (base as NSString).pathExtension.lowercased()
            return !inner.isEmpty && system.fileExtensions.contains(inner)
        })
        let folder = candidate.folderHints
        if !named.isEmpty, !folder.isEmpty, named.isDisjoint(with: folder) {
            return .failure(SkippedSave(
                name: name,
                reason: "Its name says \(Self.systemList(named)) but its folder says \(Self.systemList(folder)). Not imported."
            ))
        }
        let hinted = !named.isEmpty ? named : folder
        let fits = Set(SystemID.allCases.filter { SaveFormat.of($0).accepts(extension: ext, size: size) })
        let eligible = (hinted.isEmpty ? fits : hinted.intersection(fits))

        var otherSystemMatch: LibraryGame?
        for tier in TitleIndex.Tier.allCases {
            let matches = index.games(named: base, tier: tier, saveExtension: ext)
            if otherSystemMatch == nil { otherSystemMatch = matches.first { !eligible.contains($0.systemID) } }
            let choices = matches.filter { eligible.contains($0.systemID) }
            guard !choices.isEmpty else { continue }
            guard choices.count == 1, let game = choices.first else {
                let names = choices.prefix(4).map { "\($0.displayName) (\(Self.shortSystem($0.systemID)))" }
                return .failure(SkippedSave(
                    name: name,
                    reason: "Fits more than one game: \(names.joined(separator: ", ")). Rename it to match one game's file."
                ))
            }
            let header: Data
            do {
                header = try CoordinatedRead.run(candidate.url) { try Self.readHeader($0) }
            } catch {
                return .failure(SaveFolderScanner.readError(name, error))
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
        guard let other = otherSystemMatch else {
            return .failure(SkippedSave(
                name: name,
                reason: eligible.isEmpty
                    ? SaveFolderScanner.otherSystemReason
                    : "No game in your library has this name. Import the game first, or rename the save to match its file."
            ))
        }
        if !hinted.isEmpty, !hinted.contains(other.systemID) {
            return .failure(SkippedSave(
                name: name,
                reason: "Its folder or name says \(Self.systemList(hinted)), but it matches \(other.displayName) (\(Self.shortSystem(other.systemID))). Not imported."
            ))
        }
        return .failure(SkippedSave(name: name, reason: rejection(ext: ext, size: size, system: other.systemID)))
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
            let importer = self.importer
            let plan = try CoordinatedRead.run(candidate.url) {
                try importer.planPSPFolderImport(from: $0, for: game, paths: paths, fileManager: fileManager)
            }
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
    /// reads the save is marked to boot fresh (`FreshBoot`) just before the install; if that
    /// fails, its save isn't touched. The caller makes sure no game is running.
    public func commit(
        _ batch: SaveImportBatch,
        replaceExisting: Bool,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default
    ) -> SaveImportOutcome {
        var outcome = SaveImportOutcome()
        for item in batch.items {
            // Cancelled: the saves not yet started stay as they are; one already installing
            // has finished by the time this loop looks again.
            if Task.isCancelled {
                outcome.failed.append(SkippedSave(name: item.sourceName, reason: "Cancelled."))
                continue
            }
            // Re-checked now: the destination may have appeared since the summary was shown.
            let exists = item.plan.check == .pspFolder
                ? SaveGameImporter.existingPSPSlot(for: item.plan.destinationURL, fileManager: fileManager) != nil
                : fileManager.fileExists(atPath: item.plan.destinationURL.path)
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
            // Markers go in once the staged copy has passed its checks, right before it's
            // installed; if anything fails from there, each game's previous marker comes back.
            let previous = Dictionary(uniqueKeysWithValues: item.gameIDs.map { ($0, FreshBoot.marker($0, paths: paths)) })
            var marked = false
            do {
                try importer.commitImport(
                    plan: plan,
                    from: item.sourceURL,
                    overwrite: replaceExisting,
                    fileManager: fileManager,
                    beforeInstall: {
                        marked = true
                        for id in item.gameIDs {
                            try FreshBoot.mark(id, paths: paths, fileManager: fileManager)
                        }
                    }
                )
                outcome.imported.append(item)
            } catch {
                if marked {
                    for (id, data) in previous {
                        FreshBoot.restore(data, for: id, paths: paths, fileManager: fileManager)
                    }
                }
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
        return (try? CoordinatedRead.run(a) { fileManager.contentsEqual(atPath: $0.path, andPath: b.path) }) ?? false
    }

    static func systemList(_ systems: Set<SystemID>) -> String {
        systems.map(shortSystem).sorted().joined(separator: "/")
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

/// A game whose save was replaced from the library must not auto-resume a quick save from
/// before the import: it carries the old save in memory, and the core would write it back on
/// exit. The marker holds the import time. Launches boot fresh until a committed quick save
/// newer than that exists (a staged one from a session that died doesn't count), and even
/// then automatic resume never falls back to a state older than the import
/// (`AutoResumeLoader.apply(notBefore:)`). Deleting the game removes the marker.
public enum FreshBoot {
    public static func mark(_ gameID: UUID, at date: Date = Date(), paths: SavePaths, fileManager: FileManager = .default) throws {
        try write(Data(String(date.timeIntervalSince1970).utf8), for: gameID, paths: paths, fileManager: fileManager)
    }

    /// When the game's save was last imported from the library, if ever.
    public static func importDate(_ gameID: UUID, paths: SavePaths) -> Date? {
        guard let data = marker(gameID, paths: paths),
              let seconds = Double(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// True while the game should boot without resuming at all.
    public static func isPending(
        _ gameID: UUID,
        system: SystemID,
        paths: SavePaths,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let imported = importDate(gameID, paths: paths) else { return false }
        let committed = SaveStateStore.entries(system: system, gameID: gameID, paths: paths, fileManager: fileManager)
        return !committed.contains { ($0.modifiedAt ?? .distantPast) > imported }
    }

    /// The marker's bytes, to put back with `restore` if an import that replaced it fails.
    public static func marker(_ gameID: UUID, paths: SavePaths) -> Data? {
        try? Data(contentsOf: paths.freshBootMarkerURL(for: gameID))
    }

    public static func restore(_ data: Data?, for gameID: UUID, paths: SavePaths, fileManager: FileManager = .default) {
        if let data {
            try? write(data, for: gameID, paths: paths, fileManager: fileManager)
        } else {
            clear(gameID, paths: paths, fileManager: fileManager)
        }
    }

    public static func clear(_ gameID: UUID, paths: SavePaths, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: paths.freshBootMarkerURL(for: gameID))
    }

    private static func write(_ data: Data, for gameID: UUID, paths: SavePaths, fileManager: FileManager) throws {
        let url = paths.freshBootMarkerURL(for: gameID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Coordinated reads

/// A coordinated read of one item, the way File Provider locations expect to be read. Kept
/// short (one folder listing, one file), and cancellable: cancelling the calling task stops a
/// read still waiting for its provider instead of blocking until the provider answers.
enum CoordinatedRead {
    private final class Pending<T>: @unchecked Sendable {
        let lock = NSLock()
        let body: (URL) throws -> T
        var result: Result<T, Error>?
        var abandoned = false
        init(_ body: @escaping (URL) throws -> T) { self.body = body }
    }

    static func run<T>(_ url: URL, _ body: @escaping (URL) throws -> T) throws -> T {
        let pending = Pending(body)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
        let done = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        coordinator.coordinate(with: [intent], queue: queue) { [intent] error in
            pending.lock.lock()
            defer {
                pending.lock.unlock()
                done.signal()
            }
            guard !pending.abandoned else { return }
            if let error {
                pending.result = .failure(error)
            } else {
                pending.result = Result { try pending.body(intent.url) }
            }
        }
        while done.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            guard Task.isCancelled else { continue }
            coordinator.cancel()
            pending.lock.lock()
            pending.abandoned = true
            let finished = pending.result
            pending.lock.unlock()
            if let finished { return try finished.get() }
            throw CancellationError()
        }
        pending.lock.lock()
        defer { pending.lock.unlock() }
        guard let result = pending.result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
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

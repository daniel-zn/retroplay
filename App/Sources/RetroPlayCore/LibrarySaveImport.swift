// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import os

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
    /// Saves for systems RetroPlay doesn't play (a Vita save, a Wii U account folder),
    /// counted but not listed.
    public var otherSystemSaves = 0
    /// What the scan looked at and why it wasn't a save, for when nothing was found
    /// ("“2026-10-30”: 1 folder, 0 files").
    public var notes: [String] = []
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
    /// Saves for systems RetroPlay doesn't play: one count line in the summary, no rows.
    public var otherSystemSaves = 0
    /// What the scan looked at (`SaveScanResult.notes`), shown when nothing was found.
    public var notes: [String] = []
    public var truncated = false

    public init(
        items: [SaveImportItem] = [],
        skipped: [SkippedSave] = [],
        ignoredFiles: Int = 0,
        otherSystemSaves: Int = 0,
        truncated: Bool = false
    ) {
        self.items = items
        self.skipped = skipped
        self.ignoredFiles = ignoredFiles
        self.otherSystemSaves = otherSystemSaves
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
    private static let linkReason = "Links aren't imported; pick the file or folder itself."
    static let otherSystemReason = "Not a save for a system RetroPlay plays."

    /// Walks the picked files and folders with `FolderWalk` (each folder listed in its own
    /// coordinated read, within the entry budget). Doesn't read file contents (names and sizes
    /// only); the planner reads what it needs.
    public static func scan(
        _ urls: [URL],
        limits: SaveScanLimits = SaveScanLimits(),
        fileManager: FileManager = .default,
        cancellation: ImportCancellation = ImportCancellation()
    ) -> SaveScanResult {
        var result = SaveScanResult()
        var budget = FolderWalk.Budget(entries: limits.maxEntries)
        for root in urls {
            // Picked items count against the limits like anything found inside a folder.
            guard budget.take() else {
                result.truncated = true
                break
            }
            do {
                let item = try CoordinatedRead.run(root, cancellation) { try FolderWalk.item($0) }
                switch item.kind {
                case .link:
                    result.skipped.append(SkippedSave(name: root.lastPathComponent, reason: linkReason))
                case .folder, .package:
                    try walk(root, limits: limits, budget: &budget, result: &result, fileManager: fileManager, cancellation: cancellation)
                case .file:
                    try classifyFile(root, item: item, displayPath: root.lastPathComponent, folders: [], limits: limits, result: &result)
                }
            } catch is CancellationError {
                result.cancelled = true
                break
            } catch is FolderWalk.Truncated {
                result.truncated = true
                break
            } catch {
                // Not known to be a file or a folder: say so rather than guess.
                result.skipped.append(readError(root.lastPathComponent, error))
            }
        }
        return result
    }

    /// At most this many notes; the rest are counted in a last one.
    static let maxNotes = 8

    private static func note(_ text: String, in result: inout SaveScanResult) {
        if result.notes.count < maxNotes {
            result.notes.append(text)
        } else if result.notes.count == maxNotes {
            result.notes.append("…")
        }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    static func readError(_ name: String, _ error: Error?) -> SkippedSave {
        SkippedSave(name: name, reason: "Couldn't read it: \(error?.localizedDescription ?? "its contents can't be looked at").")
    }

    private static func walk(
        _ root: URL,
        limits: SaveScanLimits,
        budget: inout FolderWalk.Budget,
        result: inout SaveScanResult,
        fileManager: FileManager,
        cancellation: ImportCancellation
    ) throws {
        let complete = try FolderWalk.run(
            root,
            maxDepth: limits.maxDepth,
            budget: &budget,
            fileManager: fileManager,
            cancellation: cancellation,
            unreadable: { folder, error in
                // Not downloaded, no permission: reported, and the walk goes on with the rest.
                result.skipped.append(readError(folder.path.joined(separator: "/"), error))
            }
        ) { folder, children in
            let displayPath = folder.path.joined(separator: "/")
            switch folderDecision(folder, children: children) {
            case .pspSave(let modified):
                guard result.candidates.count < limits.maxCandidates else { throw FolderWalk.Truncated() }
                result.candidates.append(SaveImportCandidate(
                    url: folder.url,
                    displayPath: displayPath,
                    kind: .pspFolder(name: folder.url.lastPathComponent),
                    folderHints: [.psp],
                    modified: modified
                ))
                return []
            case .skip(let reason):
                result.skipped.append(SkippedSave(name: displayPath, reason: reason))
                return []
            case .otherSystem:
                result.otherSystemSaves += 1
                return []
            case nil:
                break
            }
            let folders = children.filter { $0.item.kind == .folder || $0.item.kind == .package }.count
            note("“\(displayPath)”: \(count(folders, "folder")), \(count(children.count - folders, "file"))", in: &result)
            var subfolders: [FolderWalk.Child] = []
            for child in children {
                let childPath = (folder.path + [child.name]).joined(separator: "/")
                // A link could point anywhere (outside the pick, or nowhere once copied).
                if child.item.kind == .link {
                    if !child.name.hasPrefix(".") {
                        result.skipped.append(SkippedSave(name: childPath, reason: linkReason))
                    }
                    continue
                }
                let isDirectory = child.item.kind == .folder || child.item.kind == .package
                if child.name.hasPrefix(".") {
                    // Hidden folders are passed over; iCloud placeholders (".Name.sav.icloud")
                    // are worth naming.
                    if !isDirectory, child.name.hasSuffix(".icloud") {
                        let real = String(child.name.dropFirst().dropLast(".icloud".count))
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
                    if child.item.kind == .package {
                        note("“\(childPath)”: a package, not looked into", in: &result)
                    } else {
                        subfolders.append(child)
                    }
                    continue
                }
                try classifyFile(child.url, item: child.item, displayPath: childPath, folders: folder.path, limits: limits, result: &result)
            }
            return subfolders
        }
        if !complete { result.truncated = true }
    }

    private enum FolderDecision {
        case pspSave(modified: Date?)
        case skip(String)
        /// A whole save of another system (one game's Vita save, a Wii U account).
        case otherSystem
    }

    /// Vita title IDs (PCSA00017, with their sce_sys folder) and Wii U account folders
    /// (80000001): only these say a folder isn't RetroPlay's. Names like "PC" don't.
    private static let vitaTitleID = try! NSRegularExpression(pattern: #"^PCS[A-Z][0-9]{5}$"#)
    private static let wiiUAccount = try! NSRegularExpression(pattern: #"^800000[0-9a-f]{2}$"#)

    private static func matches(_ pattern: NSRegularExpression, _ name: String) -> Bool {
        pattern.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)) != nil
    }

    /// What a folder is, from its own listing: a PSP save slot (a product ID and save name,
    /// in any case, with a PARAM.SFO), a folder to skip whole (a PSP-looking slot without
    /// PARAM.SFO, a PARAM.SFO under a name that isn't a save's), another system's save (a
    /// Vita title folder with sce_sys, a Wii U account folder), or nil to look inside.
    private static func folderDecision(_ folder: FolderWalk.Folder, children: [FolderWalk.Child]) -> FolderDecision? {
        let name = folder.url.lastPathComponent
        let param = children.first { $0.name.uppercased() == "PARAM.SFO" && $0.item.kind == .file }
        if matches(vitaTitleID, name), children.contains(where: { $0.name.lowercased() == "sce_sys" }) {
            return .otherSystem
        }
        if matches(wiiUAccount, name) { return .otherSystem }
        if SaveGameImporter.isValidPSPSaveFolderName(name.uppercased()) {
            if let param { return .pspSave(modified: param.item.modified) }
            if name == name.uppercased() {
                let listed = children.count == 1 ? "1 entry listed" : "\(children.count) entries listed"
                return .skip("\(SaveGameImportError.missingPSPMetadata.localizedDescription) (\(listed))")
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
        item: FolderWalk.Item,
        displayPath: String,
        folders: [String],
        limits: SaveScanLimits,
        result: inout SaveScanResult
    ) throws {
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
            note("“\(displayPath)”: not a save file", in: &result)
            return
        }
        let size = item.size
        guard size <= limits.maxFileBytes else {
            result.skipped.append(SkippedSave(name: displayPath, reason: "Too large to be a save."))
            return
        }
        guard result.candidates.count < limits.maxCandidates else { throw FolderWalk.Truncated() }
        result.candidates.append(SaveImportCandidate(
            url: url,
            displayPath: displayPath,
            kind: .file(extension: ext, size: size),
            folderHints: hints(for: folders),
            modified: item.modified
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
        var batch = SaveImportBatch(
            skipped: scan.skipped,
            ignoredFiles: scan.ignoredFiles,
            otherSystemSaves: scan.otherSystemSaves,
            truncated: scan.truncated
        )
        batch.notes = scan.notes
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
            case .failure(let skipped) where skipped.reason == SaveFolderScanner.otherSystemReason:
                batch.otherSystemSaves += 1
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
            // The check walks the slot folder by folder, each in its own coordinated read.
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
    /// reads the save is marked to boot fresh (`FreshBoot`) just before the install; if that
    /// fails, its save isn't touched. The caller makes sure no game is running.
    public func commit(
        _ batch: SaveImportBatch,
        replaceExisting: Bool,
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default,
        cancellation: ImportCancellation = ImportCancellation()
    ) -> SaveImportOutcome {
        var outcome = SaveImportOutcome()
        for item in batch.items {
            // Cancelled: the saves not yet started stay as they are; one already installing
            // has finished by the time this loop looks again.
            if Task.isCancelled { cancellation.cancel() }
            if cancellation.isCancelled {
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
            do {
                try Self.install(
                    plan, from: item.sourceURL, overwrite: replaceExisting, gameIDs: item.gameIDs,
                    paths: paths, fileManager: fileManager, cancellation: cancellation
                )
                outcome.imported.append(item)
            } catch {
                outcome.failed.append(SkippedSave(name: item.sourceName, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    /// Writes one save (`SaveGameImporter.commitImport`) and marks the games that read it to
    /// boot fresh (`FreshBoot`). The marks go in once the staged copy has passed its checks,
    /// right before the install; if anything fails from there, each game's previous mark comes
    /// back. The library import and the in-game import both write saves through this.
    public static func install(
        _ plan: SaveGameImportPlan,
        from source: URL,
        overwrite: Bool,
        gameIDs: [UUID],
        paths: SavePaths = SavePaths(),
        fileManager: FileManager = .default,
        cancellation: ImportCancellation = ImportCancellation()
    ) throws {
        let previous = Dictionary(uniqueKeysWithValues: gameIDs.map { ($0, FreshBoot.marker($0, paths: paths)) })
        var marked = false
        do {
            try SaveGameImporter().commitImport(
                plan: plan,
                from: source,
                overwrite: overwrite,
                fileManager: fileManager,
                beforeInstall: {
                    marked = true
                    for id in gameIDs {
                        try FreshBoot.mark(id, paths: paths, fileManager: fileManager)
                    }
                },
                cancellation: cancellation
            )
        } catch {
            if marked {
                for (id, data) in previous {
                    FreshBoot.restore(data, for: id, paths: paths, fileManager: fileManager)
                }
            }
            throw error
        }
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

// MARK: - Coordinated reads and the folder walk

/// Stops an import's file work: set by Stop (and when the task running it is cancelled), and
/// checked by every listing and copy loop and by a coordinated read still waiting.
public final class ImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Throws once cancelled; a cancelled calling task counts too.
    func check() throws {
        if Task.isCancelled { cancel() }
        if isCancelled { throw CancellationError() }
    }
}

/// One coordinated read of one item, the way File Provider locations expect: kept short (one
/// folder listing, one file copy). The caller's thread waits; if the import is cancelled
/// meanwhile (or the waiting task is), the coordinator is cancelled and the read returns once
/// its accessor has ended (`body` checks the same flag in its loops, so that's soon). No lock
/// is held while it does I/O.
enum CoordinatedRead {
    private final class Outcome<T>: @unchecked Sendable {
        let lock = NSLock()
        var value: Result<T, Error>?
    }

    static func run<T>(_ url: URL, _ cancellation: ImportCancellation = ImportCancellation(), _ body: @escaping (URL) throws -> T) throws -> T {
        try cancellation.check()
        let outcome = Outcome<T>()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
        let done = DispatchSemaphore(value: 0)
        let box = UncheckedBox(body)
        coordinator.coordinate(with: [intent], queue: OperationQueue()) { [intent] error in
            let value: Result<T, Error>
            if let error {
                value = .failure(error)
            } else if cancellation.isCancelled {
                value = .failure(CancellationError())
            } else {
                // A provider's item that isn't on disk yet (a "dataless" folder or file, as
                // On My iPhone and iCloud Drive keep them on a device) is fetched when read,
                // rather than listing empty.
                let restore = Materialization.forceOnThisThread()
                value = Result { try box.value(intent.url) }
                restore()
            }
            outcome.lock.lock()
            outcome.value = value
            outcome.lock.unlock()
            done.signal()
        }
        while done.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Task.isCancelled { cancellation.cancel() }
            if cancellation.isCancelled {
                coordinator.cancel()
                // Wait (on this background thread, not Stop's) for an accessor already running
                // to see the flag and end, so the caller doesn't remove staging or give up the
                // security scope under it. Bounded, in case the coordinator never calls back.
                _ = done.wait(timeout: .now() + .seconds(5))
                throw CancellationError()
            }
        }
        outcome.lock.lock()
        defer { outcome.lock.unlock() }
        return try outcome.value!.get()
    }
}

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// The one folder walk the save import uses, for picked folders and PSP save slots alike:
/// breadth-first, each folder listed one level deep inside its own coordinated read (so a
/// provider fills it when it's asked), entry by entry, so the listing stops at the budget.
enum FolderWalk {
    static let scanLog = Logger(subsystem: "com.danielzn.retroplay", category: "SaveScan")

    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
    ]

    struct Folder {
        let url: URL
        /// Names from the walked folder (included) down to this one.
        let path: [String]
    }

    struct Child {
        let url: URL
        let name: String
        let item: Item
    }

    /// What an entry is. A File Provider (an SMB share, iCloud Drive) can leave the type out
    /// of an entry's resource values, or report stale ones; a folder taken for a file would be
    /// passed over silently. So the values are read fresh, a folder counts as a folder by any
    /// account (the values, the file system, the URL), and an entry whose type nothing reports
    /// is looked into: its listing then says what it is, and a failure there is reported.
    struct Item {
        enum Kind { case folder, file, link, package }
        let kind: Kind
        let size: Int
        let modified: Date?
    }

    /// What resource values said about an entry (nil: not reported).
    struct Reported {
        var isDirectory: Bool?
        var isRegularFile: Bool?
        var isSymbolicLink: Bool?
        var isPackage: Bool?
        var size: Int?
        var modified: Date?

        init(isDirectory: Bool? = nil, isRegularFile: Bool? = nil, isSymbolicLink: Bool? = nil,
             isPackage: Bool? = nil, size: Int? = nil, modified: Date? = nil) {
            self.isDirectory = isDirectory
            self.isRegularFile = isRegularFile
            self.isSymbolicLink = isSymbolicLink
            self.isPackage = isPackage
            self.size = size
            self.modified = modified
        }

        init(_ values: URLResourceValues) {
            self.init(
                isDirectory: values.isDirectory, isRegularFile: values.isRegularFile,
                isSymbolicLink: values.isSymbolicLink, isPackage: values.isPackage,
                size: values.fileSize, modified: values.contentModificationDate
            )
        }
    }

    /// Tests: stands in for what a File Provider reports for a URL (nil: the real values).
    nonisolated(unsafe) static var reported: (@Sendable (URL) -> Reported?)?

    /// Reads an entry's values fresh (not the copies cached on the URL) and decides what it is.
    static func item(_ url: URL) throws -> Item {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let values = try Reported(fresh.resourceValues(forKeys: keys))
        return item(url, reported: reported?(url) ?? values)
    }

    static func item(_ url: URL, reported values: Reported) -> Item {
        let size = values.size ?? 0
        if values.isSymbolicLink == true { return Item(kind: .link, size: size, modified: values.modified) }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let folder = values.isDirectory == true || (exists && isDirectory.boolValue) || url.hasDirectoryPath
        let file = !folder && (values.isRegularFile == true || values.isDirectory == false || exists)
        let kind: Item.Kind = folder ? (values.isPackage == true ? .package : .folder) : file ? .file : .folder
        // What a provider reports, in every build (Console on a Mac shows it for a device;
        // names are redacted unless a debugger is attached).
        scanLog.notice(
            "RP_SCAN \(url.lastPathComponent, privacy: .private) reported isDirectory=\(String(describing: values.isDirectory), privacy: .public) isRegularFile=\(String(describing: values.isRegularFile), privacy: .public) exists=\(exists, privacy: .public) fsDirectory=\(isDirectory.boolValue, privacy: .public) hasDirectoryPath=\(url.hasDirectoryPath, privacy: .public) -> \(String(describing: kind), privacy: .public)"
        )
        return Item(kind: kind, size: size, modified: values.modified)
    }

    /// Thrown by a visitor to stop the walk at a limit it keeps (candidates).
    struct Truncated: Error {}

    /// Tests: told after each folder listing how many entries it pulled (the budget's peek
    /// included). Not set in the app.
    nonisolated(unsafe) static var listed: (@Sendable (URL, Int) -> Void)?

    /// Tests: stand in for what the bulk listing (the enumerator) and the plain directory read
    /// return for a folder (nil: the real listing). On a device, a provider's folder that isn't
    /// on disk yet can list nothing through the first.
    nonisolated(unsafe) static var bulkListing: (@Sendable (URL) -> [URL]?)?
    nonisolated(unsafe) static var plainListing: (@Sendable (URL) -> [URL]?)?
    /// Tests: stand in for `contentsOfDirectory(atPath:)`, and for the listing of the picked URL
    /// outside the coordinated read (nil: the real ones).
    nonisolated(unsafe) static var pathListing: (@Sendable (URL) -> [URL]?)?
    nonisolated(unsafe) static var uncoordinatedListing: (@Sendable (URL) -> [URL]?)?

    /// A folder that listed nothing though its metadata says it holds entries.
    struct EmptyListing: LocalizedError {
        /// How many entries it holds (nil: its contents aren't on this device yet).
        let heldEntries: Int?
        var errorDescription: String? {
            let held = heldEntries.map { $0 == 1 ? "it holds 1 item" : "it holds \($0) items" }
                ?? "its contents aren't on this iPhone yet"
            return "Files listed nothing in it, but \(held). Open it in Files so its contents download, then import again"
        }
    }

    /// Entries left to look at, shared by everything one import walks.
    struct Budget {
        var entries: Int
        mutating func take() -> Bool {
            guard entries > 0 else { return false }
            entries -= 1
            return true
        }
    }

    /// Walks `root`. `visit` gets each folder with its children and returns the subfolders to
    /// go into. A folder that can't be listed goes to `unreadable` (which may throw to stop).
    /// Returns false if the budget ran out or a folder sat deeper than `maxDepth`.
    static func run(
        _ root: URL,
        maxDepth: Int,
        budget: inout Budget,
        fileManager: FileManager,
        cancellation: ImportCancellation,
        unreadable: (Folder, Error?) throws -> Void,
        visit: (Folder, [Child]) throws -> [Child]
    ) throws -> Bool {
        var complete = true
        var queue = [Folder(url: root, path: [root.lastPathComponent])]
        var next = 0
        while next < queue.count {
            let folder = queue[next]
            next += 1
            try cancellation.check()
            let listing: (children: [Child], exhausted: Bool, error: Error?)
            do {
                listing = try list(folder.url, budget: budget.entries, fileManager: fileManager, cancellation: cancellation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                scanLog.notice("RP_SCAN list failed: \(error.localizedDescription, privacy: .public)")
                try unreadable(folder, error)
                continue
            }
            if let error = listing.error {
                scanLog.notice("RP_SCAN list failed: \(error.localizedDescription, privacy: .public)")
                try unreadable(folder, error)
                continue
            }
            scanLog.notice("RP_SCAN listed \(listing.children.count, privacy: .public) entries at depth \(folder.path.count, privacy: .public)")
            budget.entries -= listing.children.count
            if listing.exhausted { complete = false }
            for sub in try visit(folder, listing.children) {
                if folder.path.count >= maxDepth {
                    complete = false
                } else {
                    queue.append(Folder(url: sub.url, path: folder.path + [sub.name]))
                }
            }
            if listing.exhausted { return false }
        }
        return complete
    }

    /// One folder's children, at most `budget` of them (`exhausted` when there were more),
    /// read inside one coordinated read of that folder.
    private static func list(
        _ url: URL,
        budget: Int,
        fileManager: FileManager,
        cancellation: ImportCancellation
    ) throws -> (children: [Child], exhausted: Bool, error: Error?) {
        var children: [Child] = []
        var pulled = 0
        var failure: Error?
        defer { listed?(url, pulled) }
        /// One more entry; non-nil when the listing has to stop there.
        func take(_ next: URL) throws -> (children: [Child], exhausted: Bool, error: Error?)? {
            pulled += 1
            try cancellation.check()
            guard children.count < budget else { return (children, true, nil) }
            // Listed but not looked at (no search permission): the folder can't be read.
            guard let item = try? item(next) else {
                return ([], false, failure ?? CocoaError(.fileReadNoPermission))
            }
            children.append(Child(url: next, name: next.lastPathComponent, item: item))
            return nil
        }
        // Inside the folder's coordinated read: the enumerator, and when it lists nothing, the
        // plain directory reads (a provider's folder, an SMB share, can list nothing through
        // one and everything through another, with no error).
        let inside: (children: [Child], exhausted: Bool, error: Error?)? = try CoordinatedRead.run(url, cancellation) { readURL in
            if readURL != url {
                scanLog.notice("RP_SCAN the coordinator gave another URL to read than the one picked")
            }
            let nextEntry: () -> URL?
            if let given = bulkListing?(readURL) {
                var remaining = given.makeIterator()
                nextEntry = { remaining.next() }
            } else {
                guard let entries = fileManager.enumerator(
                    at: readURL,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsSubdirectoryDescendants],
                    errorHandler: { _, error in
                        failure = error
                        return false
                    }
                ) else { return ([], false, CocoaError(.fileReadUnknown)) }
                nextEntry = { entries.nextObject() as? URL }
            }
            while let next = nextEntry() {
                if let early = try take(next) { return early }
            }
            if let failure { return ([], false, failure) }
            guard pulled == 0 else { return nil }
            let plain = plainListing?(readURL) ?? (try? fileManager.contentsOfDirectory(at: readURL, includingPropertiesForKeys: nil)) ?? []
            scanLog.notice("RP_SCAN the enumerator listed 0 entries; contentsOfDirectory(at:) lists \(plain.count, privacy: .public)")
            var again = plain
            if again.isEmpty {
                let names = pathListing.map { $0(readURL)?.map(\.lastPathComponent) ?? [] }
                    ?? (try? fileManager.contentsOfDirectory(atPath: readURL.path)) ?? []
                scanLog.notice("RP_SCAN contentsOfDirectory(atPath:) lists \(names.count, privacy: .public)")
                again = names.map { readURL.appendingPathComponent($0) }
            }
            for next in again {
                if let early = try take(next) { return early }
            }
            return nil
        }
        if let inside { return inside }
        if pulled == 0 {
            // Every listing in the coordinated read came back empty: the picked URL itself, as
            // the picker handed it over (its security scope), outside the coordinator.
            let outside = uncoordinatedListing?(url) ?? (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            scanLog.notice("RP_SCAN the picked URL, outside the coordinated read, lists \(outside.count, privacy: .public)")
            for next in outside {
                if let early = try take(next) { return early }
            }
            if children.isEmpty, let held = DirectoryMetadata.heldEntries(url) {
                // Nothing listed by any means, though the folder's metadata says it holds
                // entries (or that they aren't on disk yet): said, not taken for empty.
                scanLog.notice("RP_SCAN every listing is empty where the folder holds \(held.map { String($0) } ?? "unknown (dataless)", privacy: .public)")
                return ([], false, EmptyListing(heldEntries: held))
            }
        }
        return (children.sorted { $0.name < $1.name }, false, nil)
    }
}

/// What a folder's own metadata says about its contents, without listing it.
enum DirectoryMetadata {
    /// Tests: stands in for the folder's metadata (nil: the real `stat`).
    nonisolated(unsafe) static var stat: (@Sendable (URL) -> (links: Int, dataless: Bool)?)?

    /// Entries the folder holds by its metadata: `.some(n)` with n > 0 from its link count (APFS
    /// counts each entry), `.some(nil)` when it's a dataless folder (contents not on disk), and
    /// nil when its metadata doesn't say it holds anything.
    static func heldEntries(_ url: URL) -> Int?? {
        guard let info = stat?(url) ?? statInfo(url) else { return nil }
        if info.dataless { return .some(nil) }
        // A folder's link count is 2 ("." and its entry in the parent) plus its entries on
        // APFS; other file systems report 1 or 2 whatever it holds.
        return info.links > 2 ? .some(info.links - 2) : nil
    }

    private static func statInfo(_ url: URL) -> (links: Int, dataless: Bool)? {
        var info = Darwin.stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return (Int(info.st_nlink), info.st_flags & UInt32(SF_DATALESS) != 0)
    }
}

/// Lets this thread's reads fetch a provider's items that aren't on disk yet ("dataless"), for
/// the length of one coordinated read; the thread's previous setting comes back after.
enum Materialization {
    static func forceOnThisThread() -> () -> Void {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        let set = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_ON)
        if set != 0 {
            FolderWalk.scanLog.notice("RP_SCAN couldn't turn on materializing: errno \(errno, privacy: .public)")
            return {}
        }
        return {
            if previous >= 0 {
                _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous)
            }
        }
    }
}

// MARK: - Security-scoped access

/// Keeps every picked URL readable from the scan until the commit (or the summary closes);
/// files inside a picked folder are covered by the folder's access.
public final class SecurityScopedAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [URL]

    /// Picked URLs whose access couldn't be started and that can't be read without it (a pick
    /// inside the app's own folder needs no access, so it isn't counted).
    public let refused: [URL]

    /// `start`: tests stand in for starting a URL's access.
    public init(
        _ urls: [URL],
        fileManager: FileManager = .default,
        start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
    ) {
        var started: [URL] = []
        var refused: [URL] = []
        for url in urls {
            let granted = start(url)
            let readable = fileManager.isReadableFile(atPath: url.path)
            FolderWalk.scanLog.notice(
                "RP_SCAN pick \(url.lastPathComponent, privacy: .private) access=\(granted, privacy: .public) readable=\(readable, privacy: .public)"
            )
            if granted { started.append(url) } else if !readable { refused.append(url) }
        }
        self.started = started
        self.refused = refused
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

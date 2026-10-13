// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import Combine

/// A picked file that could not be copied in. The rest of its batch still imports.
public struct LibraryImportFailure: Sendable, Equatable {
    public var fileName: String
    public var reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

/// What one import pass did with the picked files.
public struct LibraryImportSummary: Sendable, Equatable {
    public var added: [LibraryGame] = []
    /// Picked files skipped because the same game file is already in the library, earlier in the
    /// same pick, or already in Documents/Games (the folder scan adds those).
    public var duplicates: [String] = []
    /// Picked files skipped because no bundled core plays them.
    public var unsupported: [String] = []
    /// Picked files that could not be read or copied.
    public var failed: [LibraryImportFailure] = []

    public init() {}
}

/// Persists the user library as JSON under Application Support and copies imported games into
/// Documents/Games (visible in Files, alongside Saves/ and States/).
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var games: [LibraryGame] = []
    /// Set when `library.json` exists but cannot be decoded; cleared on successful load.
    @Published public private(set) var libraryLoadFailureMessage: String?
    /// Files currently being copied in by `importInBackground`.
    @Published public private(set) var importsInProgress = 0
    /// Rows whose ROM is no longer in Documents/Games (removed via Files). Saves are kept.
    @Published public private(set) var missingGameIDs: Set<UUID> = []
    /// Copy of an unreadable `library.json`, taken before anything could overwrite it.
    public private(set) var corruptLibraryBackupURL: URL?

    private let fileManager: FileManager
    private let importer: ROMImporter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let documentsDirectoryURL: URL
    private let savePaths: SavePaths
    private let covers: CoverArtStore
    /// Games/ file names claimed by an in-flight import or scan, so neither picks them twice.
    private var reservedFileNames: Set<String> = []
    private var isScanningGamesFolder = false
    /// The latest `importInBackground` batch. Each batch waits for the one before it, so its
    /// duplicate check sees every file an earlier, still-running batch adds.
    private var lastImportBatch: Task<Void, Never>?

    public init(
        fileManager: FileManager = .default,
        importer: ROMImporter = ROMImporter(),
        documentsDirectoryURL: URL? = nil,
        supportDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.importer = importer
        self.savePaths = SavePaths(
            fileManager: fileManager,
            documentsURL: documentsDirectoryURL,
            supportURL: supportDirectoryURL
        )
        self.documentsDirectoryURL = savePaths.documentsURL
        self.covers = CoverArtStore(fileManager: fileManager, paths: savePaths)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try? savePaths.migrateLegacyLayout(fileManager: fileManager)
        try? savePaths.migrateAppDataOutOfDocuments(fileManager: fileManager)
        try? ensureDirectories()
        load()
    }

    /// Documents/Games — sandbox copies of user-picked files only.
    public var gamesDirectoryURL: URL { savePaths.gamesDirectory }

    /// Legacy name; same as `gamesDirectoryURL`.
    public var romsDirectoryURL: URL { gamesDirectoryURL }

    /// Folders counted in Settings → Storage: games, battery saves (incl. PSP memstick), states.
    public var storageDirectoryURLs: [URL] {
        [savePaths.gamesDirectory, savePaths.savesDirectory, savePaths.statesDirectory]
    }

    public var libraryFileURL: URL { savePaths.libraryFileURL }

    public func absoluteURL(for game: LibraryGame) -> URL {
        savePaths.gameROMURL(forRelativePath: game.relativePath)
    }

    public func load() {
        libraryLoadFailureMessage = nil
        guard fileManager.fileExists(atPath: libraryFileURL.path) else {
            games = []
            return
        }
        do {
            let data = try Data(contentsOf: libraryFileURL)
            var loaded = try decoder.decode([LibraryGame].self, from: data)
                .sorted { $0.dateAdded > $1.dateAdded }
            let renamed = Self.cleanLegacyDisplayNames(&loaded)
            games = loaded
            if renamed { try? save() }
        } catch {
            games = []
            libraryLoadFailureMessage = error.localizedDescription
            backUpCorruptLibrary()
        }
    }

    /// Rows imported before `ROMImporter.displayName(fromFileName:)` cleaned titles still carry the
    /// raw file base name ("Legend of Zelda, The (USA)"). Renames exactly those rows; returns true
    /// when anything changed. Idempotent: a cleaned name no longer equals the file's raw base name,
    /// so later loads leave it alone, and any name the user typed is never touched.
    @discardableResult
    nonisolated static func cleanLegacyDisplayNames(_ games: inout [LibraryGame]) -> Bool {
        var changed = false
        for index in games.indices {
            if let cleaned = cleanedLegacyDisplayName(for: games[index]) {
                games[index].displayName = cleaned
                changed = true
            }
        }
        return changed
    }

    /// The cleaned title when `game.displayName` is still the raw name import derived from the
    /// original file, else nil. Import names rows from the picked file (`Game (USA).nds` →
    /// "Game (USA)") but may store it as `Game (USA)-1.nds` after a base-name clash
    /// (`uniqueFileName`), so both the stored base and that base minus a trailing `-N` count.
    nonisolated static func cleanedLegacyDisplayName(for game: LibraryGame) -> String? {
        let fileName = (game.relativePath as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension
        let storedBase = (fileName as NSString).deletingPathExtension
        var rawNames = [storedBase]
        if let suffix = storedBase.range(of: #"-[0-9]+$"#, options: .regularExpression),
           suffix.lowerBound > storedBase.startIndex {
            rawNames.append(String(storedBase[..<suffix.lowerBound]))
        }
        guard rawNames.contains(game.displayName) else { return nil }
        let originalFileName = ext.isEmpty ? game.displayName : "\(game.displayName).\(ext)"
        let cleaned = ROMImporter.displayName(fromFileName: originalFileName)
        guard !cleaned.isEmpty, cleaned != game.displayName else { return nil }
        return cleaned
    }

    /// Keeps the unreadable file as `library.json.corrupt-<timestamp>`; the next save replaces the original.
    private func backUpCorruptLibrary() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var backup = libraryFileURL.deletingLastPathComponent()
            .appendingPathComponent("library.json.corrupt-\(stamp)", isDirectory: false)
        var index = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = libraryFileURL.deletingLastPathComponent()
                .appendingPathComponent("library.json.corrupt-\(stamp)-\(index)", isDirectory: false)
            index += 1
        }
        do {
            try fileManager.copyItem(at: libraryFileURL, to: backup)
            corruptLibraryBackupURL = backup
        } catch {
            corruptLibraryBackupURL = nil
        }
    }

    public func save() throws {
        try ensureDirectories()
        let data = try encoder.encode(games)
        try data.write(to: libraryFileURL, options: [.atomic])
    }

    // MARK: - Import

    /// Copy security-scoped picks into Documents/Games and append library rows (synchronous).
    @discardableResult
    public func importFiles(from urls: [URL]) throws -> [LibraryGame] {
        try importSummary(from: urls).added
    }

    /// Synchronous import with skip details. Prefer `importInBackground` from UI code: this path
    /// does not wait for a background batch that is still copying.
    public func importSummary(from urls: [URL]) throws -> LibraryImportSummary {
        try ensureDirectories()
        let plan = planImport(urls)
        defer { releaseReservations(plan.jobs) }
        let staged = Self.stage(plan.jobs, existing: existingLibraryFiles(), paths: savePaths, importer: importer)
        return try commit(staged, plan: plan)
    }

    /// Copies and reads game metadata off the main actor; rows publish on the main actor when
    /// the whole batch is in. Security-scoped access stays open until each copy finishes. A file
    /// that cannot be read or copied lands in `failed` and the rest of the batch still imports;
    /// only a failed library save rolls the batch back. Batches run one after another, so a pick
    /// made while an earlier import is still copying is checked against that import's files.
    public func importInBackground(from urls: [URL]) async throws -> LibraryImportSummary {
        try ensureDirectories()
        let plan = planImport(urls)
        importsInProgress += plan.jobs.count
        defer {
            importsInProgress -= plan.jobs.count
            releaseReservations(plan.jobs)
        }
        let previous = lastImportBatch
        let batch = Task { () async throws -> LibraryImportSummary in
            await previous?.value
            let jobs = plan.jobs
            // Read after the previous batch committed, so its rows count as existing.
            let existing = self.existingLibraryFiles()
            let paths = self.savePaths
            let importer = self.importer
            let staged = await Task.detached(priority: .userInitiated) {
                Self.stage(jobs, existing: existing, paths: paths, importer: importer)
            }.value
            return try self.commit(staged, plan: plan)
        }
        lastImportBatch = Task { _ = await batch.result }
        let summary = try await batch.value
        if !plan.inGamesFolder.isEmpty {
            // Picks already in Games/ were not copied; the scan gives any new one its row.
            await reconcileWithGamesFolder()
        }
        return summary
    }

    struct ImportJob: Sendable {
        let source: URL
        let originalName: String
        /// Relative to Games/. A PS1 `.cue` goes in its own folder ("Folder/Game.cue") with
        /// the track files it names.
        let destinationName: String
        let fileExtension: String
        /// Picked files a `.cue` sheet names, copied next to it without rows of their own.
        var companions: [URL] = []
        /// Track names the sheet lists, to report any that weren't picked.
        var expectedCompanions: [String] = []
    }

    struct ImportPlan: Sendable {
        var jobs: [ImportJob] = []
        var unsupported: [String] = []
        /// Picks that already are top-level files in Games/ (Files → RetroPlay → Games). They are
        /// never copied next to themselves; the folder scan owns them.
        var inGamesFolder: [String] = []
    }

    struct ExistingFile: Sendable {
        let url: URL
        let name: String
    }

    enum StagedFile: Sendable {
        case added(LibraryGame, URL)
        case duplicate(String)
        case failed(LibraryImportFailure)
    }

    /// Picks each destination name on the main actor and reserves it.
    private func planImport(_ urls: [URL]) -> ImportPlan {
        var plan = ImportPlan()
        var taken = takenBaseNames()
        let gamesFolder = Self.resolvedPath(of: gamesDirectoryURL)
        // A PS1 disc picked as .cue + .bin: the tracks travel with their sheet.
        var tracksForCue: [URL: (picked: [URL], expected: [String])] = [:]
        var companionPaths = Set<String>()
        for cue in urls where cue.pathExtension.lowercased() == "cue" {
            let accessed = cue.startAccessingSecurityScopedResource()
            let names = CueSheet.referencedFiles(at: cue)
            if accessed { cue.stopAccessingSecurityScopedResource() }
            let picked = names.compactMap { name in
                urls.first { $0.lastPathComponent.lowercased() == name.lowercased() }
            }
            tracksForCue[cue] = (picked, names)
            companionPaths.formUnion(picked.map(\.path))
        }
        for url in urls where !companionPaths.contains(url.path) {
            let ext = url.pathExtension.lowercased()
            let originalName = url.lastPathComponent
            guard ImportContentTypes.isSupportedExtension(ext),
                  importer.classify(fileExtension: ext) != nil,
                  SavePaths.isSafeFileName(originalName)
            else {
                plan.unsupported.append(originalName)
                continue
            }
            if Self.resolvedPath(of: url.deletingLastPathComponent()) == gamesFolder {
                plan.inGamesFolder.append(originalName)
                continue
            }
            if let tracks = tracksForCue[url] {
                let base = (originalName as NSString).deletingPathExtension
                let folder = Self.uniqueFileName(for: base, takenBaseNames: taken)
                taken.insert(GameArtifactCleanup.baseName(of: folder))
                reservedFileNames.insert(folder)
                plan.jobs.append(ImportJob(
                    source: url,
                    originalName: originalName,
                    destinationName: "\(folder)/\(originalName)",
                    fileExtension: ext,
                    companions: tracks.picked,
                    expectedCompanions: tracks.expected
                ))
                continue
            }
            let name = Self.uniqueFileName(for: originalName, takenBaseNames: taken)
            taken.insert(GameArtifactCleanup.baseName(of: name))
            reservedFileNames.insert(name)
            plan.jobs.append(ImportJob(
                source: url,
                originalName: originalName,
                destinationName: name,
                fileExtension: ext
            ))
        }
        return plan
    }

    /// Absolute path with `..` and symlinks resolved (the picker may hand back `/private/var/…`
    /// for a sandbox folder this app knows as `/var/…`).
    nonisolated static func resolvedPath(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func releaseReservations(_ jobs: [ImportJob]) {
        for job in jobs {
            // A disc folder job reserved its folder ("Folder/Game.cue" → "Folder").
            reservedFileNames.remove(job.destinationName.split(separator: "/").first.map(String.init) ?? job.destinationName)
        }
    }

    private func existingLibraryFiles() -> [ExistingFile] {
        games.map { ExistingFile(url: absoluteURL(for: $0), name: ($0.relativePath as NSString).lastPathComponent) }
    }

    /// Base names (case-folded, no extension) already used by a row, a reservation, or a file in
    /// Games/. Saves and states are keyed by base name, so two games must never share one.
    private func takenBaseNames() -> Set<String> {
        var taken = Set(games.map { GameArtifactCleanup.baseName(of: $0.relativePath) })
        for name in reservedFileNames {
            taken.insert(GameArtifactCleanup.baseName(of: name))
        }
        if let onDisk = try? fileManager.contentsOfDirectory(atPath: gamesDirectoryURL.path) {
            for name in onDisk where !name.hasPrefix(".") {
                taken.insert(GameArtifactCleanup.baseName(of: name))
            }
        }
        return taken
    }

    /// `Game.gba` → `Game-1.gba` when any game already uses the base name `Game`, whatever its extension.
    nonisolated static func uniqueFileName(for originalName: String, takenBaseNames taken: Set<String>) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var candidate = originalName
        var index = 1
        while taken.contains(GameArtifactCleanup.baseName(of: candidate)) {
            let suffix = "-\(index)"
            candidate = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            index += 1
        }
        return candidate
    }

    /// Off-main work, one file at a time: duplicate check, copy, product ID, cover. A file that
    /// cannot be read or copied becomes `.failed` and leaves nothing behind; the others go on.
    /// Each copied file joins the duplicate check, so a game picked twice is added once.
    nonisolated static func stage(
        _ jobs: [ImportJob],
        existing: [ExistingFile],
        paths: SavePaths,
        importer: ROMImporter
    ) -> [StagedFile] {
        let fileManager = FileManager.default
        let covers = CoverArtStore(fileManager: fileManager, paths: paths)
        var known = existing
        var staged: [StagedFile] = []
        for job in jobs {
            let result = stageFile(job, known: known, paths: paths, importer: importer, fileManager: fileManager)
            if case .added(let entry, let destination) = result {
                known.append(ExistingFile(url: destination, name: job.destinationName))
                _ = try? covers.installFromGameFile(
                    gameID: entry.id,
                    fileURL: destination,
                    system: entry.systemID
                )
            }
            staged.append(result)
        }
        return staged
    }

    nonisolated private static func stageFile(
        _ job: ImportJob,
        known: [ExistingFile],
        paths: SavePaths,
        importer: ROMImporter,
        fileManager: FileManager
    ) -> StagedFile {
        let accessed = job.source.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                job.source.stopAccessingSecurityScopedResource()
            }
        }
        do {
            // A coordinated read makes iCloud Drive download a placeholder before it is read.
            return try coordinatedRead(of: job.source) { source -> StagedFile in
                if Self.isDuplicate(source, originalName: job.originalName, of: known) {
                    return .duplicate(job.originalName)
                }

                let destination = paths.gamesDirectory.appendingPathComponent(job.destinationName)
                if job.destinationName.contains("/") {
                    try copyDiscFolder(job, sheet: source, to: destination, fileManager: fileManager)
                } else {
                    // Copy under a hidden name first so a Games/ scan never sees a partial file.
                    let temporary = paths.gamesDirectory
                        .appendingPathComponent(".importing-\(UUID().uuidString)-\(job.destinationName)")
                    do {
                        try fileManager.copyItem(at: source, to: temporary)
                        try fileManager.moveItem(at: temporary, to: destination)
                    } catch {
                        try? fileManager.removeItem(at: temporary)
                        throw error
                    }
                }

                do {
                    let entry = try importer.makeLibraryEntry(
                        originalFileName: job.originalName,
                        sandboxRelativePath: job.destinationName,
                        fileExtension: job.fileExtension,
                        sandboxFileURL: destination
                    )
                    return .added(entry, destination)
                } catch {
                    try? fileManager.removeItem(at: destination)
                    if job.destinationName.contains("/") {
                        try? fileManager.removeItem(at: destination.deletingLastPathComponent())
                    }
                    throw error
                }
            }
        } catch {
            return .failed(LibraryImportFailure(fileName: job.originalName, reason: error.localizedDescription))
        }
    }

    /// A `.cue` sheet and the tracks it names, copied into the game's own folder. Built under
    /// a hidden name and moved in whole, so a Games/ scan never sees half a disc.
    nonisolated private static func copyDiscFolder(
        _ job: ImportJob,
        sheet: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let pickedNames = Set(job.companions.map { $0.lastPathComponent.lowercased() })
        let missing = job.expectedCompanions.filter { !pickedNames.contains($0.lowercased()) }
        guard !job.expectedCompanions.isEmpty, missing.isEmpty else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: missing.isEmpty
                    ? "\(job.originalName) doesn't name any track files."
                    : "Pick \(job.originalName) together with its track files (missing: \(missing.joined(separator: ", ")))."
            ])
        }
        let folder = destination.deletingLastPathComponent()
        let temporary = folder.deletingLastPathComponent()
            .appendingPathComponent(".importing-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sheet, to: temporary.appendingPathComponent(job.originalName))
            for track in job.companions {
                let accessed = track.startAccessingSecurityScopedResource()
                defer { if accessed { track.stopAccessingSecurityScopedResource() } }
                try coordinatedRead(of: track) { readURL in
                    try fileManager.copyItem(at: readURL, to: temporary.appendingPathComponent(track.lastPathComponent))
                }
            }
            try fileManager.moveItem(at: temporary, to: folder)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// Runs `body` inside an `NSFileCoordinator` read of `url`, passing the URL to read from.
    nonisolated static func coordinatedRead<T>(of url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { readURL in
            outcome = Result { try body(readURL) }
        }
        if let outcome {
            return try outcome.get()
        }
        throw coordinationError ?? CocoaError(.fileReadUnknown)
    }

    nonisolated private static func rollBack(_ staged: [StagedFile], paths: SavePaths) {
        let fileManager = FileManager.default
        let covers = CoverArtStore(fileManager: fileManager, paths: paths)
        for case .added(let entry, let destination) in staged {
            try? fileManager.removeItem(at: destination)
            if entry.relativePath.contains("/") {
                try? fileManager.removeItem(at: destination.deletingLastPathComponent())
            }
            try? covers.removeCover(forGameID: entry.id)
        }
    }

    private func commit(_ staged: [StagedFile], plan: ImportPlan) throws -> LibraryImportSummary {
        var summary = LibraryImportSummary()
        summary.unsupported = plan.unsupported
        summary.duplicates = plan.inGamesFolder
        for item in staged {
            switch item {
            case .added(let entry, _):
                games.insert(entry, at: 0)
                summary.added.append(entry)
            case .duplicate(let name):
                summary.duplicates.append(name)
            case .failed(let failure):
                summary.failed.append(failure)
            }
        }
        guard !summary.added.isEmpty else { return summary }
        do {
            try save()
        } catch {
            let ids = Set(summary.added.map(\.id))
            games.removeAll { ids.contains($0.id) }
            Self.rollBack(staged, paths: savePaths)
            throw error
        }
        return summary
    }

    // MARK: - Duplicate detection

    /// Same size and name as a library file, or same size and same first/last 64 KB.
    nonisolated static func isDuplicate(_ source: URL, originalName: String, of existing: [ExistingFile]) -> Bool {
        guard let size = fileSize(source) else { return false }
        var sourcePrint: Data?
        for file in existing {
            guard fileSize(file.url) == size else { continue }
            if file.name == originalName { return true }
            if sourcePrint == nil {
                sourcePrint = fingerprint(of: source)
                if sourcePrint == nil { return false }
            }
            if fingerprint(of: file.url) == sourcePrint { return true }
        }
        return false
    }

    nonisolated static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let size = values.fileSize
        else { return nil }
        return Int64(size)
    }

    /// SHA-256 of the first and last 64 KB — cheap even for multi-GB ISOs.
    nonisolated static func fingerprint(of url: URL) -> Data? {
        let window = 64 * 1024
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            var hasher = SHA256()
            let head = try handle.read(upToCount: window) ?? Data()
            hasher.update(data: head)
            let end = try handle.seekToEnd()
            if end > UInt64(window) {
                try handle.seek(toOffset: end - UInt64(window))
                hasher.update(data: try handle.read(upToCount: window) ?? Data())
            }
            return Data(hasher.finalize())
        } catch {
            return nil
        }
    }

    // MARK: - Games folder scan

    /// Adds rows for ROMs dropped into Documents/Games via Files (known extensions only) and
    /// flags rows whose ROM is gone. Never deletes anything; a new file whose base name another
    /// game already uses is renamed (`Game-1.nds`) so the two never share saves.
    public func reconcileWithGamesFolder() async {
        guard !isScanningGamesFolder else { return }
        isScanningGamesFolder = true
        defer { isScanningGamesFolder = false }

        let found = newGamesFolderFiles()
        if !found.isEmpty {
            let paths = savePaths
            let importer = importer
            let entries = await Task.detached(priority: .utility) {
                Self.makeScannedEntries(found, paths: paths, importer: importer)
            }.value
            for job in found {
                reservedFileNames.remove(job.destinationName)
            }
            let known = Set(games.map(\.relativePath))
            let fresh = entries.filter { !known.contains($0.relativePath) }
            if !fresh.isEmpty {
                games.insert(contentsOf: fresh, at: 0)
                try? save()
            }
        }
        refreshMissingGames()
    }

    public func refreshMissingGames() {
        let missing = Set(games.filter { !fileManager.fileExists(atPath: absoluteURL(for: $0).path) }.map(\.id))
        if missing != missingGameIDs {
            missingGameIDs = missing
        }
    }

    /// Lists untracked top-level ROMs, renames base-name clashes, and reserves the final names.
    private func newGamesFolderFiles() -> [ImportJob] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: gamesDirectoryURL.path) else {
            return []
        }
        let known = Set(games.map { $0.relativePath.lowercased() })
        var taken = Set(games.map { GameArtifactCleanup.baseName(of: $0.relativePath) })
        for name in reservedFileNames {
            taken.insert(GameArtifactCleanup.baseName(of: name))
        }
        let visible = names.filter { !$0.hasPrefix(".") }
        let onDiskBases = Set(visible.map { GameArtifactCleanup.baseName(of: $0) })

        // Track files a top-level .cue sheet names belong to that sheet's game.
        let cueTracks = Set(visible
            .filter { ($0 as NSString).pathExtension.lowercased() == "cue" }
            .flatMap { CueSheet.referencedFiles(at: gamesDirectoryURL.appendingPathComponent($0)) }
            .map { $0.lowercased() })

        var jobs: [ImportJob] = []
        for name in visible.sorted() {
            guard !known.contains(name.lowercased()), !reservedFileNames.contains(name),
                  !cueTracks.contains(name.lowercased())
            else { continue }
            let ext = (name as NSString).pathExtension.lowercased()
            let url = gamesDirectoryURL.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard ImportContentTypes.isSupportedExtension(ext),
                  importer.classify(fileExtension: ext) != nil,
                  SavePaths.isSafeFileName(name),
                  fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue
            else { continue }

            var finalName = name
            if taken.contains(GameArtifactCleanup.baseName(of: name)) {
                finalName = Self.uniqueFileName(for: name, takenBaseNames: taken.union(onDiskBases))
                do {
                    try fileManager.moveItem(at: url, to: gamesDirectoryURL.appendingPathComponent(finalName))
                } catch {
                    continue
                }
            }
            taken.insert(GameArtifactCleanup.baseName(of: finalName))
            reservedFileNames.insert(finalName)
            jobs.append(ImportJob(
                source: gamesDirectoryURL.appendingPathComponent(finalName),
                originalName: name,
                destinationName: finalName,
                fileExtension: ext
            ))
        }
        return jobs
    }

    nonisolated private static func makeScannedEntries(
        _ jobs: [ImportJob],
        paths: SavePaths,
        importer: ROMImporter
    ) -> [LibraryGame] {
        let covers = CoverArtStore(fileManager: .default, paths: paths)
        return jobs.compactMap { job in
            guard let entry = try? importer.makeLibraryEntry(
                originalFileName: job.originalName,
                sandboxRelativePath: job.destinationName,
                fileExtension: job.fileExtension,
                sandboxFileURL: job.source
            ) else { return nil }
            _ = try? covers.installFromGameFile(gameID: entry.id, fileURL: job.source, system: entry.systemID)
            return entry
        }
    }

    // MARK: - Remove

    /// Drops the row first, then removes its files best-effort. A ROM already gone (deleted in
    /// Files) is fine; files another row still uses are kept.
    @discardableResult
    public func remove(_ game: LibraryGame) throws -> GameArtifactCleanupResult {
        games.removeAll { $0.id == game.id }
        missingGameIDs.remove(game.id)
        try save()
        return try GameArtifactCleanup.removeArtifacts(
            for: game,
            paths: savePaths,
            otherGames: games,
            fileManager: fileManager
        )
    }

    private func ensureDirectories() throws {
        try savePaths.ensureDirectories(fileManager: fileManager)
        try covers.ensureDirectory()
    }

    public func games(matching system: SystemID?) -> [LibraryGame] {
        guard let system else { return games }
        return games.filter { $0.systemID == system }
    }
}

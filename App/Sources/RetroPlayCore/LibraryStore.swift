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
    /// Picked files whose copy the player cancelled (nothing of them is left).
    public var cancelled: [String] = []
    /// Pictures picked with (or after) their games and set as those games' covers.
    public var covers: [String] = []

    public init() {}
}

/// Persists the user library as JSON under Application Support and copies imported games into
/// Documents/Games (visible in Files, alongside Saves/ and States/).
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var games: [LibraryGame] = []
    /// Bumped when the player's own pictures replace covers, so the library redraws them.
    @Published public private(set) var coversRevision = 0
    /// Set when `library.json` exists but cannot be decoded; cleared on successful load.
    @Published public private(set) var libraryLoadFailureMessage: String?
    /// Files currently being copied in by `importInBackground`.
    @Published public private(set) var importsInProgress = 0
    /// What those copies are doing, one by one.
    public let imports = GameImports()
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
        removePartialCopies()
        load()
    }

    /// Copies an import left half done when the app was ended mid-copy (their hidden
    /// `.importing-…` names), at launch, before any import starts.
    private func removePartialCopies() {
        let games = savePaths.gamesDirectory
        for name in (try? fileManager.contentsOfDirectory(atPath: games.path)) ?? [] where name.hasPrefix(".importing-") {
            try? fileManager.removeItem(at: games.appendingPathComponent(name))
        }
    }

    /// Documents/Games — sandbox copies of user-picked files only.
    public var gamesDirectoryURL: URL { savePaths.gamesDirectory }

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
        let pictures = urls.filter(CustomCovers.isImage)
        var summary = try importGames(from: urls.filter { !CustomCovers.isImage($0) })
        applyPickedCovers(pictures, Self.readPictures(pictures), to: &summary)
        return summary
    }

    private func importGames(from urls: [URL]) throws -> LibraryImportSummary {
        try ensureDirectories()
        let plan = planImport(urls, cueSheets: Self.readCueSheets(urls))
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
        let pictures = urls.filter(CustomCovers.isImage)
        var summary = try await importGamesInBackground(from: urls.filter { !CustomCovers.isImage($0) })
        let images = await Task.detached(priority: .userInitiated) { Self.readPictures(pictures) }.value
        applyPickedCovers(pictures, images, to: &summary)
        return summary
    }

    /// Pictures picked in Import become the covers of the games they're named after (picked in
    /// the same batch or already in the library); a picture matching no game is skipped.
    private func applyPickedCovers(_ pictures: [URL], _ images: [Data?], to summary: inout LibraryImportSummary) {
        guard !pictures.isEmpty else { return }
        let covers = CoverArtStore(fileManager: fileManager, paths: savePaths)
        for (picture, data) in zip(pictures, images) {
            guard let game = CustomCovers.game(forImageNamed: picture.lastPathComponent, in: games) else {
                summary.unsupported.append(picture.lastPathComponent)
                continue
            }
            if let data, (try? covers.installCustom(data, forGameID: game.id)) == true {
                summary.covers.append(picture.lastPathComponent)
            } else {
                summary.failed.append(LibraryImportFailure(
                    fileName: picture.lastPathComponent, reason: "The picture couldn't be read as an image."
                ))
            }
        }
        if !summary.covers.isEmpty { coversRevision += 1 }
    }

    /// The picked pictures' bytes (nil: unreadable), read off the main actor.
    nonisolated static func readPictures(_ pictures: [URL]) -> [Data?] {
        pictures.map { picture in
            let accessed = picture.startAccessingSecurityScopedResource()
            defer { if accessed { picture.stopAccessingSecurityScopedResource() } }
            return try? CoordinatedRead.run(picture) { try Data(contentsOf: $0) }
        }
    }

    private func importGamesInBackground(from urls: [URL]) async throws -> LibraryImportSummary {
        try ensureDirectories()
        // Nothing reads a picked file on the main actor: a stalled share would freeze the app.
        let cueSheets = await Task.detached(priority: .userInitiated) { Self.readCueSheets(urls) }.value
        let plan = planImport(urls, cueSheets: cueSheets)
        let control = imports.begin(plan.jobs)
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
                Self.stage(jobs, existing: existing, paths: paths, importer: importer, control: control)
            }.value
            do {
                let summary = try self.commit(staged, plan: plan, stopped: self.imports.stopReasons)
                for (job, item) in zip(jobs, staged) {
                    self.imports.finish(job.id, item.importState(stopped: self.imports.stopReasons[job.id]))
                }
                return summary
            } catch {
                for job in jobs { self.imports.finish(job.id, .failed(error.localizedDescription)) }
                throw error
            }
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
        let id = UUID()
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
        case cancelled(UUID, String)

        func importState(stopped reason: String?) -> GameImports.State {
            switch self {
            case .added, .duplicate: return .done
            case .failed(let failure): return .failed(failure.reason)
            case .cancelled: return reason.map { .failed($0) } ?? .cancelled
            }
        }
    }

    /// A background import's cancels and progress reports, by job.
    struct ImportControl: Sendable {
        var cancellations: [UUID: ImportCancellation] = [:]
        /// Bytes copied so far, of the total when known.
        var progress: @Sendable (UUID, Int64, Int64?) -> Void = { _, _, _ in }

        func cancellation(for job: ImportJob) -> ImportCancellation {
            cancellations[job.id] ?? ImportCancellation()
        }
    }

    /// The track names each picked `.cue` sheet lists.
    nonisolated static func readCueSheets(_ urls: [URL]) -> [URL: [String]] {
        var sheets: [URL: [String]] = [:]
        for cue in urls where cue.pathExtension.lowercased() == "cue" {
            let accessed = cue.startAccessingSecurityScopedResource()
            sheets[cue] = CueSheet.referencedFiles(at: cue)
            if accessed { cue.stopAccessingSecurityScopedResource() }
        }
        return sheets
    }

    /// Picks each destination name on the main actor and reserves it. Reads no picked file
    /// (`cueSheets` were read off it).
    private func planImport(_ urls: [URL], cueSheets: [URL: [String]]) -> ImportPlan {
        var plan = ImportPlan()
        var taken = takenBaseNames()
        let gamesFolder = Self.resolvedPath(of: gamesDirectoryURL)
        // A PS1 disc picked as .cue + .bin: the tracks travel with their sheet.
        var tracksForCue: [URL: (picked: [URL], expected: [String])] = [:]
        var companionPaths = Set<String>()
        for (cue, names) in cueSheets {
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

    /// Absolute path with `..` resolved and `/private/var/…` (as the picker may hand back a
    /// sandbox folder this app knows as `/var/…`) as `/var/…`. From the path alone: resolving
    /// symlinks would ask the file system, and a picked file's share may not answer.
    nonisolated static func resolvedPath(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
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
        importer: ROMImporter,
        control: ImportControl = ImportControl()
    ) -> [StagedFile] {
        let fileManager = FileManager.default
        let covers = CoverArtStore(fileManager: fileManager, paths: paths)
        var known = existing
        var staged: [StagedFile] = []
        for job in jobs {
            let result = stageFile(job, known: known, paths: paths, importer: importer, fileManager: fileManager, control: control)
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
        fileManager: FileManager,
        control: ImportControl
    ) -> StagedFile {
        let accessed = job.source.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                job.source.stopAccessingSecurityScopedResource()
            }
        }
        let cancellation = control.cancellation(for: job)
        do {
            // A coordinated read makes iCloud Drive (or an SMB share) fetch the file before it
            // is read; a cancel ends the read, the copy inside it, and the coordination.
            return try CoordinatedRead.run(job.source, cancellation) { source -> StagedFile in
                if Self.isDuplicate(source, originalName: job.originalName, of: known) {
                    return .duplicate(job.originalName)
                }

                let destination = paths.gamesDirectory.appendingPathComponent(job.destinationName)
                if job.destinationName.contains("/") {
                    try copyDiscFolder(job, sheet: source, to: destination, fileManager: fileManager,
                                       cancellation: cancellation, control: control)
                } else {
                    // Copy under a hidden name first so a Games/ scan never sees a partial file.
                    let temporary = paths.gamesDirectory
                        .appendingPathComponent(".importing-\(UUID().uuidString)-\(job.destinationName)")
                    let total = fileSize(source)
                    do {
                        try copyFile(source, to: temporary, cancellation: cancellation) {
                            control.progress(job.id, $0, total)
                        }
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
        } catch is CancellationError {
            return .cancelled(job.id, job.originalName)
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
        fileManager: FileManager,
        cancellation: ImportCancellation,
        control: ImportControl
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
            let sizes = job.companions.map { track -> Int64? in
                let accessed = track.startAccessingSecurityScopedResource()
                defer { if accessed { track.stopAccessingSecurityScopedResource() } }
                return fileSize(track)
            }
            let total = sizes.contains(nil) ? nil : sizes.reduce(0) { $0 + ($1 ?? 0) }
            var before: Int64 = 0
            for (track, size) in zip(job.companions, sizes) {
                let accessed = track.startAccessingSecurityScopedResource()
                defer { if accessed { track.stopAccessingSecurityScopedResource() } }
                let base = before
                try CoordinatedRead.run(track, cancellation) { readURL in
                    try copyFile(readURL, to: temporary.appendingPathComponent(track.lastPathComponent),
                                 cancellation: cancellation) { control.progress(job.id, base + $0, total) }
                }
                before += size ?? 0
            }
            try fileManager.moveItem(at: temporary, to: folder)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// Tests: a pause after each chunk a game copy writes, so a copy lasts long enough to watch.
    nonisolated(unsafe) public static var testChunkPause: TimeInterval = 0

    /// Copies a picked file a megabyte at a time, reporting the bytes copied so far and stopping
    /// at the next megabyte once cancelled (the caller removes the partial copy).
    nonisolated static func copyFile(
        _ source: URL,
        to destination: URL,
        cancellation: ImportCancellation,
        progress: (Int64) -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied: Int64 = 0
        while try autoreleasepool(invoking: { () throws -> Bool in
            try cancellation.check()
            guard let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty else { return false }
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress(copied)
            if testChunkPause > 0 { Thread.sleep(forTimeInterval: testChunkPause) }
            return true
        }) {}
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

    /// `stopped`: imports `GameImports.stopAll` ended, by job, with why; they count as failed.
    private func commit(_ staged: [StagedFile], plan: ImportPlan, stopped: [UUID: String] = [:]) throws -> LibraryImportSummary {
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
            case .cancelled(let id, let name):
                if let reason = stopped[id] {
                    summary.failed.append(LibraryImportFailure(fileName: name, reason: reason))
                } else {
                    summary.cancelled.append(name)
                }
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
        KeptSaves.attach(to: summary.added, library: games, paths: savePaths, fileManager: fileManager)
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

        // The disk reads run off the main thread; only the bookkeeping comes back to it.
        let folder = gamesDirectoryURL
        let files = games.map { ($0.id, absoluteURL(for: $0).path) }
        let scan = await Task.detached(priority: .utility) {
            Self.scanGamesFolder(folder, files: files)
        }.value

        let found = newGamesFolderFiles(scan)
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
                KeptSaves.attach(to: fresh, library: games, paths: savePaths, fileManager: fileManager)
            }
        }
        applyFolderCovers(scan.images)
        if scan.missing != missingGameIDs {
            missingGameIDs = scan.missing
        }
    }

    struct GamesFolderScan: Sendable {
        /// Top-level names, hidden files left out.
        var names: [String] = []
        /// Track files the top-level .cue sheets name (they belong to that sheet's game).
        var cueTracks: Set<String> = []
        var images: [(url: URL, modified: Date)] = []
        /// Games whose file is gone.
        var missing: Set<UUID> = []
    }

    nonisolated static func scanGamesFolder(_ folder: URL, files: [(UUID, String)]) -> GamesFolderScan {
        let fileManager = FileManager.default
        var scan = GamesFolderScan()
        scan.names = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
        scan.cueTracks = Set(scan.names
            .filter { ($0 as NSString).pathExtension.lowercased() == "cue" }
            .flatMap { CueSheet.referencedFiles(at: folder.appendingPathComponent($0)) }
            .map { $0.lowercased() })
        scan.images = CustomCovers.imagesInGamesFolder(folder, fileManager: fileManager)
        scan.missing = Set(files.filter { !fileManager.fileExists(atPath: $0.1) }.map(\.0))
        return scan
    }

    /// Pictures dropped into Games/ (Files → RetroPlay → Games) named like a game become its
    /// cover; a picture is applied again only when it changes after the cover was set.
    private func applyFolderCovers(_ images: [(url: URL, modified: Date)]) {
        let covers = CoverArtStore(fileManager: fileManager, paths: savePaths)
        var changed = false
        for (url, modified) in images {
            guard let game = CustomCovers.game(forImageNamed: url.lastPathComponent, in: games) else { continue }
            if covers.origin(forGameID: game.id) == .custom,
               let current = covers.coverModified(forGameID: game.id), current >= modified {
                continue
            }
            if let data = try? Data(contentsOf: url), (try? covers.installCustom(data, forGameID: game.id)) == true {
                // The cover carries the picture's date, so "changed since" is an exact comparison
                // (a picture dated in the future isn't applied again on every scan).
                try? fileManager.setAttributes([.modificationDate: modified],
                                               ofItemAtPath: covers.coverURL(forGameID: game.id).path)
                changed = true
            }
        }
        if changed { coversRevision += 1 }
    }

    /// Checks one game's file (a tap): the others keep what the last full check found.
    @discardableResult
    public func refreshMissing(_ game: LibraryGame) -> Bool {
        let missing = !fileManager.fileExists(atPath: absoluteURL(for: game).path)
        if missing != missingGameIDs.contains(game.id) {
            if missing { missingGameIDs.insert(game.id) } else { missingGameIDs.remove(game.id) }
        }
        return missing
    }

    /// Lists untracked top-level ROMs, renames base-name clashes, and reserves the final names.
    private func newGamesFolderFiles(_ scan: GamesFolderScan) -> [ImportJob] {
        let visible = scan.names, cueTracks = scan.cueTracks
        let known = Set(games.map { $0.relativePath.lowercased() })
        var taken = Set(games.map { GameArtifactCleanup.baseName(of: $0.relativePath) })
        for name in reservedFileNames {
            taken.insert(GameArtifactCleanup.baseName(of: name))
        }
        let onDiskBases = Set(visible.map { GameArtifactCleanup.baseName(of: $0) })

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

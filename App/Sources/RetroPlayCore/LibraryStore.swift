import Foundation
import Combine

/// Persists the user library as JSON under Documents and copies imported ROMs into Documents/ROMs.
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var games: [LibraryGame] = []

    private let fileManager: FileManager
    private let importer: ROMImporter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        importer: ROMImporter = ROMImporter()
    ) {
        self.fileManager = fileManager
        self.importer = importer
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        try? ensureDirectories()
        load()
    }

    /// Documents/ROMs — sandbox copies of user-picked files only.
    public var romsDirectoryURL: URL {
        documentsDirectoryURL.appendingPathComponent("ROMs", isDirectory: true)
    }

    public var libraryFileURL: URL {
        documentsDirectoryURL.appendingPathComponent("library.json", isDirectory: false)
    }

    private var documentsDirectoryURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func absoluteURL(for game: LibraryGame) -> URL {
        romsDirectoryURL.appendingPathComponent(game.relativePath)
    }

    public func load() {
        guard fileManager.fileExists(atPath: libraryFileURL.path) else {
            games = []
            return
        }
        do {
            let data = try Data(contentsOf: libraryFileURL)
            games = try decoder.decode([LibraryGame].self, from: data)
                .sorted { $0.dateAdded > $1.dateAdded }
        } catch {
            games = []
        }
    }

    public func save() throws {
        try ensureDirectories()
        let data = try encoder.encode(games)
        try data.write(to: libraryFileURL, options: [.atomic])
    }

    /// Copy security-scoped picks into Documents/ROMs and append library rows.
    @discardableResult
    public func importFiles(from urls: [URL]) throws -> [LibraryGame] {
        try ensureDirectories()
        var added: [LibraryGame] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let ext = url.pathExtension.lowercased()
            guard ImportContentTypes.isSupportedExtension(ext),
                  importer.classify(fileExtension: ext) != nil
            else {
                continue
            }

            let originalName = url.lastPathComponent
            let uniqueName = uniqueFileName(for: originalName)
            let destination = romsDirectoryURL.appendingPathComponent(uniqueName)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)

            let entry = try importer.makeLibraryEntry(
                originalFileName: originalName,
                sandboxRelativePath: uniqueName,
                fileExtension: ext
            )
            games.insert(entry, at: 0)
            added.append(entry)
        }

        if !added.isEmpty {
            try save()
        }
        return added
    }

    public func remove(_ game: LibraryGame) throws {
        games.removeAll { $0.id == game.id }
        let fileURL = absoluteURL(for: game)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try save()
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: romsDirectoryURL, withIntermediateDirectories: true)
    }

    public func games(matching system: SystemID?) -> [LibraryGame] {
        guard let system else { return games }
        return games.filter { $0.systemID == system }
    }

    private func uniqueFileName(for originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var candidate = originalName
        var index = 1
        while fileManager.fileExists(atPath: romsDirectoryURL.appendingPathComponent(candidate).path)
            || games.contains(where: { $0.relativePath == candidate })
        {
            let suffix = "-\(index)"
            candidate = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            index += 1
        }
        return candidate
    }
}

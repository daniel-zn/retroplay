import Foundation

/// Optional user cover art beside Documents/ROMs. No bundled game art.
/// Not marked Sendable: holds FileManager and is used from the main-actor UI / LibraryStore.
public struct CoverArtStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var coversDirectoryURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    public func coverURL(forGameID id: UUID) -> URL {
        coversDirectoryURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    public func hasCover(forGameID id: UUID) -> Bool {
        fileManager.fileExists(atPath: coverURL(forGameID: id).path)
    }

    public func ensureDirectory() throws {
        try fileManager.createDirectory(at: coversDirectoryURL, withIntermediateDirectories: true)
    }
}

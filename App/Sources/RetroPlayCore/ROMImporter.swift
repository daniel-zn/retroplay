import Foundation

/// User-imported library entry. Paths are always inside the app sandbox after import.
public struct LibraryGame: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public var systemID: SystemID
    /// Relative path under the app's Documents/ROMs directory — never a hardcoded sample ROM.
    public var relativePath: String
    public var dateAdded: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        systemID: SystemID,
        relativePath: String,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.systemID = systemID
        self.relativePath = relativePath
        self.dateAdded = dateAdded
    }
}

/// Stub importer: classifies by extension and records sandbox-relative paths.
/// Wire to UIDocumentPicker / `.fileImporter` in the app target — do not invent ROM URLs.
public struct ROMImporter: Sendable {
    public init() {}

    public func classify(fileExtension: String) -> SystemID? {
        SystemRegistry.system(forFileExtension: fileExtension)
    }

    /// Build a library row after the app has copied a user-picked file into the sandbox.
    public func makeLibraryEntry(
        originalFileName: String,
        sandboxRelativePath: String,
        fileExtension: String
    ) throws -> LibraryGame {
        guard let system = classify(fileExtension: fileExtension) else {
            throw EmulatorCoreError.romLoadFailed("Unsupported extension: \(fileExtension)")
        }
        let name = (originalFileName as NSString).deletingPathExtension
        return LibraryGame(
            displayName: name.isEmpty ? originalFileName : name,
            systemID: system,
            relativePath: sandboxRelativePath
        )
    }
}

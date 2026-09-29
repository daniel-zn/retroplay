// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// User-imported library entry. Paths are always inside the app sandbox after import.
public struct LibraryGame: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var displayName: String
    public var systemID: SystemID
    /// Relative path under the app's Documents/Games directory — never a hardcoded sample ROM.
    public var relativePath: String
    public var dateAdded: Date
    /// PSP product/title ID in SAVEDATA folder form (e.g. `ULUS12345`). Nil when unknown.
    public var pspProductID: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        systemID: SystemID,
        relativePath: String,
        dateAdded: Date = Date(),
        pspProductID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.systemID = systemID
        self.relativePath = relativePath
        self.dateAdded = dateAdded
        self.pspProductID = pspProductID.flatMap { Self.normalizedPSPProductID($0) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        systemID = try container.decode(SystemID.self, forKey: .systemID)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        let rawID = try container.decodeIfPresent(String.self, forKey: .pspProductID)
        pspProductID = rawID.flatMap { Self.normalizedPSPProductID($0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(systemID, forKey: .systemID)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encodeIfPresent(pspProductID, forKey: .pspProductID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, systemID, relativePath, dateAdded, pspProductID
    }

    private static func normalizedPSPProductID(_ raw: String) -> String? {
        PSPProductIDNormalizer.normalize(raw)
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
        fileExtension: String,
        sandboxFileURL: URL? = nil
    ) throws -> LibraryGame {
        guard let system = classify(fileExtension: fileExtension) else {
            throw EmulatorCoreError.romLoadFailed("Unsupported extension: \(fileExtension)")
        }
        let name = Self.displayName(fromFileName: originalFileName)
        var pspProductID: String?
        if system == .psp, let sandboxFileURL {
            if case .found(let id) = PSPProductIDExtractor.extract(from: sandboxFileURL) {
                pspProductID = id
            }
        }
        return LibraryGame(
            displayName: name.isEmpty ? originalFileName : name,
            systemID: system,
            relativePath: sandboxRelativePath,
            pspProductID: pspProductID
        )
    }

    /// Library title from a ROM file name: drops the extension, region/revision tags
    /// such as "(USA)" or "[!]" and disc product codes such as "ULUS10238", and moves a
    /// trailing article to the front ("Legend of Zelda, The - …" → "The Legend of Zelda - …").
    /// Falls back to the bare file name when cleaning would leave nothing.
    public static func displayName(fromFileName fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        var name = base.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"(?i)\b[A-Z]{4}[-_ ]?\d{5}\b"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        if let match = name.firstMatch(of: /^(.+?), (The|A|An)(\s+-\s+.*|:.*)?$/) {
            name = "\(match.2) \(match.1)\(match.3 ?? "")"
        }
        if !name.isEmpty { return name }
        return base.isEmpty ? fileName : base
    }
}

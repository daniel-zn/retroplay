import UniformTypeIdentifiers

/// P0 ROM / disc extensions accepted by the Files importer.
public enum ImportContentTypes {
    public static let fileExtensions: [String] = [
        "gba", "agb", "mb",
        "n64", "z64", "v64",
        "nds", "dsi",
        "iso", "cso", "chd", "pbp",
        "zip",
    ]

    /// Broad types plus per-extension UTTypes so `.fileImporter` surfaces ROMs in Files.
    public static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.item, .data, .archive, .diskImage]
        for ext in fileExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    public static func isSupportedExtension(_ ext: String) -> Bool {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return fileExtensions.contains(normalized)
    }
}

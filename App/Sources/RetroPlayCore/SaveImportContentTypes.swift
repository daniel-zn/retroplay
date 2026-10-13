// SPDX-License-Identifier: GPL-3.0-or-later
import UniformTypeIdentifiers

/// Battery-save / memstick artifacts accepted by the Files importer (not quick-states).
public enum SaveImportContentTypes {
    public static let batteryExtensions: [String] = [
        "sav", "srm", "eep", "fla", "sra", "mpk", "mcr",
    ]

    public static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.folder, .data, .item]
        for ext in batteryExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    public static func isBatteryExtension(_ ext: String) -> Bool {
        batteryExtensions.contains(ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    public static func isSaveStateExtension(_ ext: String) -> Bool {
        ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "state"
    }
}

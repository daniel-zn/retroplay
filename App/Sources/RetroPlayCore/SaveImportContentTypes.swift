// SPDX-License-Identifier: GPL-3.0-or-later
import UniformTypeIdentifiers

/// Battery-save / memstick artifacts accepted by the Files importer (not quick-states).
public enum SaveImportContentTypes {
    /// Every extension some core reads as a battery save (see `SaveFormat`).
    public static let batteryExtensions: [String] = SaveFormat.batteryExtensions.sorted()

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
        let ext = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        // RetroArch numbers its slots .state1… and keeps the auto slot as .state.auto; mGBA
        // writes .ss0–.ss9, PPSSPP .ppst.
        if ext == "state" || ext == "auto" || ext == "ppst" { return true }
        if ext.hasPrefix("state"), Int(ext.dropFirst(5)) != nil { return true }
        if ext.count == 3, ext.hasPrefix("ss"), ext.last?.isNumber == true { return true }
        return false
    }
}

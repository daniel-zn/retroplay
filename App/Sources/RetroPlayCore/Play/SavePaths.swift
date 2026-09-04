import Foundation

/// Sandbox layout for saves / states under Documents (no invented ROM paths).
public struct SavePaths: Sendable {
    public let documentsURL: URL

    public init(fileManager: FileManager = .default) {
        self.documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public var romsDirectory: URL {
        documentsURL.appendingPathComponent("ROMs", isDirectory: true)
    }

    public var savesDirectory: URL {
        documentsURL.appendingPathComponent("Saves", isDirectory: true)
    }

    public var statesDirectory: URL {
        documentsURL.appendingPathComponent("States", isDirectory: true)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for url in [romsDirectory, savesDirectory, statesDirectory] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// SRAM file mirroring the ROM relative path under Saves/ with `.sav`.
    public func sramURL(forRelativeROMPath relativePath: String) -> URL {
        let base = (relativePath as NSString).deletingPathExtension
        return savesDirectory.appendingPathComponent(base + ".sav")
    }

    public func stateURL(forRelativeROMPath relativePath: String, slot: Int) -> URL {
        let base = (relativePath as NSString).deletingPathExtension
        return statesDirectory.appendingPathComponent("\(base).slot\(slot).state")
    }
}

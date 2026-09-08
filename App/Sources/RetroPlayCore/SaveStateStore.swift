import Foundation

/// Sandbox save-state paths. Never ship states or ROMs in git.
public enum SaveStateStore: Sendable {
    /// `Documents/Saves/<system>/<gameUUID>/quick.state`
    public static func quickSaveURL(system: SystemID, gameID: UUID) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent("Saves", isDirectory: true)
            .appendingPathComponent(system.rawValue, isDirectory: true)
            .appendingPathComponent(gameID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("quick.state", isDirectory: false)
    }

    public static func quickSaveExists(system: SystemID, gameID: UUID) -> Bool {
        guard let url = try? quickSaveURL(system: system, gameID: gameID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

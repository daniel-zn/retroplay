import Foundation

/// Bridge contract for audio/video/input frames and save states.
/// Implementations will wrap bundled cores later.
/// No core binaries are included in this scaffold.
public protocol EmulatorCore: AnyObject, Sendable {
    var systemID: SystemID { get }
    var coreName: String { get }

    func loadROM(at url: URL) async throws
    func start()
    func pause()
    func resume()
    func stop()

    func saveState(to url: URL) async throws
    func loadState(from url: URL) async throws
}

public enum EmulatorCoreError: Error, Sendable, LocalizedError {
    case notImplemented(String)
    case unsupportedSystem(SystemID)
    case romLoadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message): return message
        case .unsupportedSystem(let system): return "Unsupported system: \(system.displayName)"
        case .romLoadFailed(let message): return message
        }
    }
}

/// Registry of default core names per system. Actual plugin loading comes in M1+.
public enum SystemRegistry {
    public static func defaultCoreName(for system: SystemID) -> String {
        system.defaultCoreName
    }

    public static func system(forFileExtension ext: String) -> SystemID? {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return SystemID.allCases.first { $0.fileExtensions.contains(normalized) }
    }
}

/// Placeholder core used until a real bundled core is wired (M1+).
public final class StubEmulatorCore: EmulatorCore, @unchecked Sendable {
    public let systemID: SystemID
    public var coreName: String { systemID.defaultCoreName }

    public init(systemID: SystemID) {
        self.systemID = systemID
    }

    public func loadROM(at url: URL) async throws {
        throw EmulatorCoreError.notImplemented(
            "\(coreName) not bundled yet — scaffold only. ROM at \(url.lastPathComponent)"
        )
    }

    public func start() {}
    public func pause() {}
    public func resume() {}
    public func stop() {}

    public func saveState(to url: URL) async throws {
        throw EmulatorCoreError.notImplemented("saveState")
    }

    public func loadState(from url: URL) async throws {
        throw EmulatorCoreError.notImplemented("loadState")
    }
}

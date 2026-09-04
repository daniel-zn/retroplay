import Foundation

/// M1 GBA core host. Links against a vendored mGBA build on Mac/Xcode — not bundled in this repo yet.
/// Until the native library is linked, `loadROM` fails honestly (same as StubEmulatorCore).
public final class MGBACore: EmulatorCore, @unchecked Sendable {
    public let systemID: SystemID = .gba
    public var coreName: String { "mGBA" }

    public private(set) var romURL: URL?

    public init() {}

    public func loadROM(at url: URL) async throws {
        guard url.pathExtension.lowercased() == "gba"
            || url.pathExtension.lowercased() == "agb"
            || url.pathExtension.lowercased() == "mb"
        else {
            throw EmulatorCoreError.romLoadFailed("Expected a GBA ROM, got .\(url.pathExtension)")
        }
        romURL = url
        // Native mGBA is not linked in the git tree yet — see App/Vendor/mGBA.md.
        throw EmulatorCoreError.notImplemented(
            "mGBA native library not linked. Follow App/Vendor/mGBA.md on Mac/Xcode, then replace this stub."
        )
    }

    public func start() {}
    public func pause() {}
    public func resume() {}
    public func stop() {
        romURL = nil
    }

    public func saveState(to url: URL) async throws {
        throw EmulatorCoreError.notImplemented("mGBA saveState — needs native core")
    }

    public func loadState(from url: URL) async throws {
        throw EmulatorCoreError.notImplemented("mGBA loadState — needs native core")
    }
}

public enum CoreFactory {
    /// Returns the production core for a system when available; otherwise a stub.
    public static func makeCore(for system: SystemID) -> any EmulatorCore {
        switch system {
        case .gba:
            return MGBACore()
        case .n64, .nds, .psp:
            return StubEmulatorCore(systemID: system)
        }
    }
}

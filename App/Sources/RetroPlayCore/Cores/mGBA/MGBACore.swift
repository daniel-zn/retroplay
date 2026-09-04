import Foundation

/// M1 GBA core host.
///
/// Native path compiles only when the app target defines `RETROPLAY_HAS_MGBA` and links
/// `mGBA.xcframework` (see `App/Vendor/mGBA.md` + Bridging/). Until then, load fails honestly.
public final class MGBACore: EmulatorCore, @unchecked Sendable {
    public let systemID: SystemID = .gba
    public var coreName: String { "mGBA" }

    public private(set) var romURL: URL?
    public private(set) var isRunning = false
    public private(set) var isPaused = false

    private weak var frameSink: EmulatorFrameSink?
    private var currentInput: GBAInput = []

    #if RETROPLAY_HAS_MGBA
    // Opaque pointer kept for the C core; filled in when native is linked.
    private var nativeCore: OpaquePointer?
    #endif

    public init() {}

    public func attachFrameSink(_ sink: EmulatorFrameSink?) {
        frameSink = sink
    }

    public func setGBAInput(_ input: GBAInput) {
        currentInput = input
        #if RETROPLAY_HAS_MGBA
        // TODO(native): core->setKeys(core, input.rawValue) once bridged.
        #endif
    }

    public func loadROM(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard ["gba", "agb", "mb"].contains(ext) else {
            throw EmulatorCoreError.romLoadFailed("Expected a GBA ROM, got .\(ext)")
        }
        romURL = url

        #if RETROPLAY_HAS_MGBA
        // TODO(native): mCoreFind(path) / mCoreLoadFile; configure video buffer; autoload save.
        throw EmulatorCoreError.notImplemented(
            "RETROPLAY_HAS_MGBA is set but native glue is not filled in yet — complete C bridge calls."
        )
        #else
        throw EmulatorCoreError.notImplemented(
            "mGBA XCFramework not linked. Build with App/Vendor/build-mgba-ios.sh on a Mac, then set RETROPLAY_HAS_MGBA."
        )
        #endif
    }

    public func start() {
        guard romURL != nil else { return }
        isRunning = true
        isPaused = false
        #if RETROPLAY_HAS_MGBA
        // TODO(native): start run-loop / display link calling core->runFrame
        #endif
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }

    public func stop() {
        isRunning = false
        isPaused = false
        romURL = nil
        #if RETROPLAY_HAS_MGBA
        // TODO(native): deinit native core
        nativeCore = nil
        #endif
    }

    public func saveState(to url: URL) async throws {
        #if RETROPLAY_HAS_MGBA
        throw EmulatorCoreError.notImplemented("mGBA saveStateNamed — wire after native core lives")
        #else
        throw EmulatorCoreError.notImplemented("mGBA saveState — needs XCFramework")
        #endif
    }

    public func loadState(from url: URL) async throws {
        #if RETROPLAY_HAS_MGBA
        throw EmulatorCoreError.notImplemented("mGBA loadStateNamed — wire after native core lives")
        #else
        throw EmulatorCoreError.notImplemented("mGBA loadState — needs XCFramework")
        #endif
    }
}

public enum CoreFactory {
    public static func makeCore(for system: SystemID) -> any EmulatorCore {
        switch system {
        case .gba:
            return MGBACore()
        case .n64, .nds, .psp:
            return StubEmulatorCore(systemID: system)
        }
    }
}

import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_MELONDS

/// Real melonDS interpreter bridge lands after XCFramework wiring on Mac (no JIT).
public final class MelonDSNativeDriver: MelonDSNativeDriving {
    public init() {}

    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "melonDS native bridge not implemented yet — XCFramework linked but driver stubs remain. See App/Vendor/melonDS.md."
        )
    }

    public func setKeys(_ bitmask: UInt32, touchX: UInt16, touchY: UInt16, touchPressed: Bool) {
        _ = bitmask
        _ = touchX
        _ = touchY
        _ = touchPressed
    }

    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("melonDS saveState — bridge pending")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("melonDS loadState — bridge pending")
    }
    public func tearDown() {}
}

#else

public final class MelonDSNativeDriver: MelonDSNativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_MELONDS and link App/Vendor/Output/melonDS.xcframework. See App/Vendor/melonDS.md."
        )
    }
    public func setKeys(_ bitmask: UInt32, touchX: UInt16, touchY: UInt16, touchPressed: Bool) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MELONDS")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MELONDS")
    }
    public func tearDown() {}
}

#endif

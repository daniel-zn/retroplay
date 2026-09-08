import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_N64

/// Real mupen64plus bridge lands after XCFramework + GLES/GLideN64 wiring on Mac.
public final class N64NativeDriver: N64NativeDriving {
    public init() {}

    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "N64 native bridge not implemented yet — XCFramework linked but driver stubs remain. See App/Vendor/mupen64plus.md."
        )
    }

    public func setKeys(_ bitmask: UInt32, stickX: Int8, stickY: Int8) {
        _ = bitmask
        _ = stickX
        _ = stickY
    }

    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("N64 saveState — bridge pending")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("N64 loadState — bridge pending")
    }
    public func tearDown() {}
}

#else

public final class N64NativeDriver: N64NativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_N64 and link App/Vendor/Output/mupen64plus.xcframework. See App/Vendor/mupen64plus.md."
        )
    }
    public func setKeys(_ bitmask: UInt32, stickX: Int8, stickY: Int8) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_N64")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_N64")
    }
    public func tearDown() {}
}

#endif

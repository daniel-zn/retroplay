import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_PPSSPP
/// Real PPSSPP C++/ObjC bridge lands here once the XCFramework is linked.
public final class PPSSPPNativeDriver: PPSSPPNativeDriving {
    public init() {}

    public func loadGame(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "PPSSPP XCFramework linked but native loadGame bridge not implemented yet."
        )
    }

    public func setKeys(_ bitmask: UInt32) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func tearDown() {}
}
#else
public final class PPSSPPNativeDriver: PPSSPPNativeDriving {
    public init() {}
    public func loadGame(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_PPSSPP and link App/Vendor/Output/PPSSPP.xcframework. See App/Vendor/PPSSPP.md."
        )
    }
    public func setKeys(_ bitmask: UInt32) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func tearDown() {}
}
#endif

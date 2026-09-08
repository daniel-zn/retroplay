import Foundation

/// Implemented in the **iOS app target** once a melonDS XCFramework is linked.
/// RetroPlayCore stays free of melonDS C++ types so the Swift package builds without the framework.
public protocol MelonDSNativeDriving: AnyObject {
    func loadROM(at url: URL) throws
    /// Button bitmask (melonDS key bits) plus optional touch (screen coords, pressed).
    func setKeys(_ bitmask: UInt32, touchX: UInt16, touchY: UInt16, touchPressed: Bool)
    func runFrame()
    func pauseAudioVideo()
    func resumeAudioVideo()
    func tearDown()
    func copyRGBAFrame() -> EmulatorVideoFrame?
    func saveState(to url: URL) throws
    func loadState(from url: URL) throws
}

public enum MelonDSNativeRegistry {
    /// Set from app init after linking melonDS XCFramework and defining RETROPLAY_HAS_MELONDS.
    nonisolated(unsafe) public static var makeDriver: (() -> MelonDSNativeDriving)?
}

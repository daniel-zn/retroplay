import Foundation

/// Implemented in the app target once a PPSSPP XCFramework is linked.
public protocol PPSSPPNativeDriving: AnyObject {
    func loadGame(at url: URL) throws
    func setKeys(_ bitmask: UInt32)
    func runFrame()
    func pauseAudioVideo()
    func resumeAudioVideo()
    func tearDown()
    func copyRGBAFrame() -> EmulatorVideoFrame?
    func saveState(to url: URL) throws
    func loadState(from url: URL) throws
}

public enum PPSSPPNativeRegistry {
    /// Set from app init after linking PPSSPP and defining RETROPLAY_HAS_PPSSPP.
    nonisolated(unsafe) public static var makeDriver: (() -> PPSSPPNativeDriving)?
}

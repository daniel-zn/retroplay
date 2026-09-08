import Foundation

/// Implemented in the **iOS app target** once a mupen64plus-next XCFramework is linked.
/// RetroPlayCore stays free of mupen C types so the Swift package builds without the framework.
public protocol N64NativeDriving: AnyObject {
    func loadROM(at url: URL) throws
    /// Button bitmask (m64p plugin BUTTON bits) plus analog stick (−128…127).
    func setKeys(_ bitmask: UInt32, stickX: Int8, stickY: Int8)
    func runFrame()
    func pauseAudioVideo()
    func resumeAudioVideo()
    func tearDown()
    func copyRGBAFrame() -> EmulatorVideoFrame?
    func saveState(to url: URL) throws
    func loadState(from url: URL) throws
}

public enum N64NativeRegistry {
    /// Set from app init after linking mupen64plus XCFramework and defining RETROPLAY_HAS_N64.
    nonisolated(unsafe) public static var makeDriver: (() -> N64NativeDriving)?
}

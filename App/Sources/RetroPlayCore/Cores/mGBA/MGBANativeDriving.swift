import Foundation

/// Implemented in the **iOS app target** (with bridging header + linked XCFramework).
/// RetroPlayCore stays free of mGBA C types so the Swift package builds without the framework.
public protocol MGBANativeDriving: AnyObject {
    func loadROM(at url: URL) throws
    func setKeys(_ bitmask: UInt32)
    func reset()
    func runFrame()
    func pauseAudioVideo()
    func resumeAudioVideo()
    func tearDown()
    /// Copy current video buffer as RGBA8888 (width*height*4 bytes), stride in bytes.
    func copyRGBAFrame() -> EmulatorVideoFrame?
    func saveState(to url: URL) throws
    func loadState(from url: URL) throws
}

public enum MGBANativeRegistry {
    /// Set from the app target after linking `mGBA.xcframework`, e.g. in `App` init:
    /// `MGBANativeRegistry.makeDriver = { MGBANativeDriver() }`
    public static var makeDriver: (() -> MGBANativeDriving)?
}

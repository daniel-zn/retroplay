// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One native emulator (mGBA, PPSSPP, mupen64plus-next, melonDS) behind a C/C++ bridge.
///
/// Implementations live in the **app target** next to the bridging header so this
/// package builds without any XCFramework. Every method is called on the single
/// shared emulation thread (`EmulationThread`), never on the main thread, so a
/// driver never needs its own locking.
public protocol NativeEmulatorDriver: AnyObject {
    /// Load and boot a game. Battery saves go where `saves` says for this system
    /// (`sramURL`, `n64SRAMURL`, `pspMemstickDirectory`) so import and cleanup find them.
    func load(romURL: URL, saves: SavePaths) throws

    /// Frames per second the core wants to be driven at (valid after `load`).
    var frameRate: Double { get }
    /// Sample rate of `readAudio` output, in Hz. 0 means the core produces no audio.
    var audioSampleRate: Double { get }

    /// Apply the latest input before `runFrame`.
    func setInput(_ input: EmulatorInputState)
    /// Emulate exactly one video frame.
    func runFrame()
    /// Copy up to `maxFrames` interleaved stereo Int16 frames produced so far.
    /// Returns the number of frames written (0 when drained).
    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int
    /// Copy the most recent video frame as RGBX8888 (alpha ignored). False if none yet.
    func copyVideo(into buffer: VideoFrameBuffer) -> Bool

    var supportsSaveStates: Bool { get }
    func saveState(to url: URL) throws
    func loadState(from url: URL) throws

    /// Hard reset of the running game, if supported.
    var supportsReset: Bool { get }
    func reset()

    /// Write battery/SRAM to disk if it changed. Called periodically and before teardown.
    func flushSaveData()
    /// True once the core stopped on an unrecoverable error (frames no longer advance).
    var hadRuntimeError: Bool { get }

    /// Fast-forward started or stopped. Cores that pace themselves to real time
    /// (PPSSPP) must stop throttling, or the extra frames per tick are slept away.
    func setFastForward(_ enabled: Bool)
    /// Release every native resource. The driver is not used again afterwards.
    func tearDown()
}

public extension NativeEmulatorDriver {
    var supportsReset: Bool { false }
    func reset() {}
    func flushSaveData() {}
    var hadRuntimeError: Bool { false }
    func setFastForward(_ enabled: Bool) {}
}

/// Factories registered by the app target once the native XCFrameworks are linked.
public enum NativeDriverRegistry {
    public typealias Factory = @Sendable () -> any NativeEmulatorDriver

    nonisolated(unsafe) private static var factories: [SystemID: Factory] = [:]
    private static let lock = NSLock()

    public static func register(_ system: SystemID, factory: @escaping Factory) {
        lock.lock()
        defer { lock.unlock() }
        factories[system] = factory
    }

    public static func factory(for system: SystemID) -> Factory? {
        lock.lock()
        defer { lock.unlock() }
        return factories[system]
    }

    public static func isRegistered(_ system: SystemID) -> Bool {
        factory(for: system) != nil
    }
}

/// Reusable RGBX8888 pixel buffer a driver writes each frame into (no per-frame allocation).
public final class VideoFrameBuffer {
    public private(set) var width = 0
    public private(set) var height = 0
    public private(set) var bytesPerRow = 0
    private var storage: UnsafeMutableRawPointer?
    private var capacity = 0

    public init() {}

    deinit {
        storage?.deallocate()
    }

    /// Size the buffer for a tightly packed `width × height` frame and return its base address.
    public func prepare(width: Int, height: Int) -> UnsafeMutablePointer<UInt8> {
        let rowBytes = max(0, width) * 4
        let needed = max(4, rowBytes * max(0, height))
        if needed > capacity {
            storage?.deallocate()
            storage = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
            capacity = needed
        }
        self.width = max(0, width)
        self.height = max(0, height)
        self.bytesPerRow = rowBytes
        return storage!.assumingMemoryBound(to: UInt8.self)
    }

    public var bytes: UnsafePointer<UInt8>? {
        guard let storage, width > 0, height > 0 else { return nil }
        return UnsafePointer(storage.assumingMemoryBound(to: UInt8.self))
    }

    public var byteCount: Int { bytesPerRow * height }
}

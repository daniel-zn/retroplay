import Foundation
import CoreGraphics

/// One rendered video frame from a core (RGBA8888 or RGB565 expanded by the host).
public struct EmulatorVideoFrame: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major pixel bytes. Layout documented by the producing core (mGBA uses its video buffer format).
    public let bytes: Data
    public let bytesPerRow: Int

    public init(width: Int, height: Int, bytes: Data, bytesPerRow: Int) {
        self.width = width
        self.height = height
        self.bytes = bytes
        self.bytesPerRow = bytesPerRow
    }
}

public protocol EmulatorFrameSink: AnyObject, Sendable {
    func coreDidProduceVideoFrame(_ frame: EmulatorVideoFrame)
    func coreDidProduceAudio(samples: UnsafePointer<Int16>, count: Int)
}

/// Button bits for GBA (matches common GBA key masks; mapped in MGBACore when native is linked).
public struct GBAInput: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let a      = GBAInput(rawValue: 1 << 0)
    public static let b      = GBAInput(rawValue: 1 << 1)
    public static let select = GBAInput(rawValue: 1 << 2)
    public static let start  = GBAInput(rawValue: 1 << 3)
    public static let right  = GBAInput(rawValue: 1 << 4)
    public static let left   = GBAInput(rawValue: 1 << 5)
    public static let up     = GBAInput(rawValue: 1 << 6)
    public static let down   = GBAInput(rawValue: 1 << 7)
    public static let r      = GBAInput(rawValue: 1 << 8)
    public static let l      = GBAInput(rawValue: 1 << 9)
}

public extension EmulatorCore {
    /// Optional hook; default no-op so stubs stay simple.
    func setGBAInput(_ input: GBAInput) {}
    func attachFrameSink(_ sink: EmulatorFrameSink?) {}
}

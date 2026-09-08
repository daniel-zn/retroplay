import Foundation

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
    /// Defaults for cores that do not take GBA input / video sinks yet.
    /// Requirements live on `EmulatorCore` so existential calls dispatch to overrides (e.g. MGBACore).
    func setGBAInput(_ input: GBAInput) {}
    func setPSPInput(_ input: PSPInput) {}
    func attachFrameSink(_ sink: EmulatorFrameSink?) {}
    var supportsSaveState: Bool { false }
    var supportsFastForward: Bool { false }
    func setFastForward(_ enabled: Bool) { _ = enabled }
}


public extension GBAInput {
    static let dpad: GBAInput = [.up, .down, .left, .right]
    static let face: GBAInput = [.a, .b, .start, .select, .l, .r]
}

/// Button bits for PSP (matches PPSSPP CTRL_* from sceCtrl.h).
public struct PSPInput: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let select   = PSPInput(rawValue: 0x0001)
    public static let start    = PSPInput(rawValue: 0x0008)
    public static let up       = PSPInput(rawValue: 0x0010)
    public static let right    = PSPInput(rawValue: 0x0020)
    public static let down     = PSPInput(rawValue: 0x0040)
    public static let left     = PSPInput(rawValue: 0x0080)
    public static let l        = PSPInput(rawValue: 0x0100)
    public static let r        = PSPInput(rawValue: 0x0200)
    public static let triangle = PSPInput(rawValue: 0x1000)
    public static let circle   = PSPInput(rawValue: 0x2000)
    public static let cross    = PSPInput(rawValue: 0x4000)
    public static let square   = PSPInput(rawValue: 0x8000)
}

public extension PSPInput {
    static let dpad: PSPInput = [.up, .down, .left, .right]
    static let face: PSPInput = [.triangle, .circle, .cross, .square]
}


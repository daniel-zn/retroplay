// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Everything the player is holding right now, in one value the UI can hand to
/// any core. `buttons` carries the system's own bit layout (`GBAInput`,
/// `PSPInput`, `N64Input`, `NDSInput` raw values).
public struct EmulatorInputState: Sendable, Equatable {
    public var buttons: UInt32
    /// Left analog stick, −1…1. X right-positive, Y up-positive.
    public var analogX: Float
    public var analogY: Float
    /// NDS bottom-screen touch in native pixels (0…255 × 0…191).
    public var touchX: UInt16
    public var touchY: UInt16
    public var touching: Bool

    public init(
        buttons: UInt32 = 0,
        analogX: Float = 0,
        analogY: Float = 0,
        touchX: UInt16 = 0,
        touchY: UInt16 = 0,
        touching: Bool = false
    ) {
        self.buttons = buttons
        self.analogX = analogX
        self.analogY = analogY
        self.touchX = touchX
        self.touchY = touchY
        self.touching = touching
    }

    public static let neutral = EmulatorInputState()

    /// Analog as signed 8-bit (N64 range ±`maxMagnitude`).
    public func analogInt8(maxMagnitude: Float = 80) -> (x: Int8, y: Int8) {
        let x = (max(-1, min(1, analogX)) * maxMagnitude).rounded()
        let y = (max(-1, min(1, analogY)) * maxMagnitude).rounded()
        return (Int8(clamping: Int(x)), Int8(clamping: Int(y)))
    }
}

/// Button bits for GBA (matches mGBA key masks).
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


/// Button bits matching mupen64plus-core `m64p_plugin.h` BUTTON flags.
public struct N64Input: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let dpadRight = N64Input(rawValue: 0x0001)
    public static let dpadLeft  = N64Input(rawValue: 0x0002)
    public static let dpadDown  = N64Input(rawValue: 0x0004)
    public static let dpadUp    = N64Input(rawValue: 0x0008)
    public static let start     = N64Input(rawValue: 0x0010)
    public static let z         = N64Input(rawValue: 0x2000)
    public static let b         = N64Input(rawValue: 0x4000)
    public static let a         = N64Input(rawValue: 0x8000)
    public static let cRight    = N64Input(rawValue: 0x0100)
    public static let cLeft     = N64Input(rawValue: 0x0200)
    public static let cDown     = N64Input(rawValue: 0x0400)
    public static let cUp       = N64Input(rawValue: 0x0800)
    public static let r         = N64Input(rawValue: 0x1000)
    public static let l         = N64Input(rawValue: 0x0020)
}

public extension N64Input {
    static let dpad: N64Input = [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]
    static let cButtons: N64Input = [.cUp, .cDown, .cLeft, .cRight]
}

/// Analog stick for N64 (−128…127). Digital pad scaffolding may leave this at zero.
public struct N64AnalogStick: Sendable, Hashable {
    public var x: Int8
    public var y: Int8

    public init(x: Int8 = 0, y: Int8 = 0) {
        self.x = x
        self.y = y
    }

    public static let zero = N64AnalogStick(x: 0, y: 0)
}

/// Button bits for NDS (melonDS key order: A B Select Start Right Left Up Down R L X Y).
public struct NDSInput: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let a      = NDSInput(rawValue: 1 << 0)
    public static let b      = NDSInput(rawValue: 1 << 1)
    public static let select = NDSInput(rawValue: 1 << 2)
    public static let start  = NDSInput(rawValue: 1 << 3)
    public static let right  = NDSInput(rawValue: 1 << 4)
    public static let left   = NDSInput(rawValue: 1 << 5)
    public static let up     = NDSInput(rawValue: 1 << 6)
    public static let down   = NDSInput(rawValue: 1 << 7)
    public static let r      = NDSInput(rawValue: 1 << 8)
    public static let l      = NDSInput(rawValue: 1 << 9)
    public static let x      = NDSInput(rawValue: 1 << 10)
    public static let y      = NDSInput(rawValue: 1 << 11)
}

public extension NDSInput {
    static let dpad: NDSInput = [.up, .down, .left, .right]
    static let face: NDSInput = [.a, .b, .x, .y]
}

/// Touchscreen sample for NDS (bottom screen). Idle = not pressed.
public struct NDSTouch: Sendable, Hashable {
    public var x: UInt16
    public var y: UInt16
    public var pressed: Bool

    public init(x: UInt16 = 0, y: UInt16 = 0, pressed: Bool = false) {
        self.x = x
        self.y = y
        self.pressed = pressed
    }

    public static let idle = NDSTouch(x: 0, y: 0, pressed: false)
}

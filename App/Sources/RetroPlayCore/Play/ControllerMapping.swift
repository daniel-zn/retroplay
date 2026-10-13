// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Physical-controller buttons by *position* (Xbox/MFi naming: south = bottom face button).
/// Keyboard keys map onto the same roles, so one table per system covers both.
public struct PadRole: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let south     = PadRole(rawValue: 1 << 0)
    public static let east      = PadRole(rawValue: 1 << 1)
    public static let west      = PadRole(rawValue: 1 << 2)
    public static let north     = PadRole(rawValue: 1 << 3)
    public static let leftShoulder  = PadRole(rawValue: 1 << 4)
    public static let rightShoulder = PadRole(rawValue: 1 << 5)
    public static let leftTrigger   = PadRole(rawValue: 1 << 6)
    public static let rightTrigger  = PadRole(rawValue: 1 << 7)
    public static let start     = PadRole(rawValue: 1 << 8)
    public static let select    = PadRole(rawValue: 1 << 9)
    public static let up        = PadRole(rawValue: 1 << 10)
    public static let down      = PadRole(rawValue: 1 << 11)
    public static let left      = PadRole(rawValue: 1 << 12)
    public static let right     = PadRole(rawValue: 1 << 13)
}

/// Snapshot of a physical controller (or keyboard) in role terms.
public struct PhysicalPadState: Sendable, Equatable {
    public var roles: PadRole
    /// −1…1, Y up-positive.
    public var leftStickX: Float
    public var leftStickY: Float
    public var rightStickX: Float
    public var rightStickY: Float

    public init(
        roles: PadRole = [],
        leftStickX: Float = 0,
        leftStickY: Float = 0,
        rightStickX: Float = 0,
        rightStickY: Float = 0
    ) {
        self.roles = roles
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
    }

    public static let neutral = PhysicalPadState()
}

/// Maps a physical pad onto a system. Face buttons follow the console's *positions*
/// (e.g. GBA A is the right-hand button, so it sits on `east`).
public enum ControllerMapping {
    /// Stick deflection that counts as a digital press (stick-as-D-pad, N64 C buttons).
    public static let digitalThreshold: Float = 0.5

    public static func map(_ pad: PhysicalPadState, for system: SystemID) -> (buttons: UInt32, analogX: Float, analogY: Float) {
        let r = pad.roles
        let stickDirs = directions(x: pad.leftStickX, y: pad.leftStickY)
        switch system {
        case .gba:
            var b: GBAInput = []
            if r.contains(.east) { b.insert(.a) }
            if r.contains(.south) { b.insert(.b) }
            if r.contains(.leftShoulder) || r.contains(.leftTrigger) { b.insert(.l) }
            if r.contains(.rightShoulder) || r.contains(.rightTrigger) { b.insert(.r) }
            if r.contains(.start) { b.insert(.start) }
            if r.contains(.select) { b.insert(.select) }
            let d = r.union(stickDirs)
            if d.contains(.up) { b.insert(.up) }
            if d.contains(.down) { b.insert(.down) }
            if d.contains(.left) { b.insert(.left) }
            if d.contains(.right) { b.insert(.right) }
            return (UInt32(b.rawValue), 0, 0)

        case .nds:
            var b: NDSInput = []
            if r.contains(.east) { b.insert(.a) }
            if r.contains(.south) { b.insert(.b) }
            if r.contains(.north) { b.insert(.x) }
            if r.contains(.west) { b.insert(.y) }
            if r.contains(.leftShoulder) || r.contains(.leftTrigger) { b.insert(.l) }
            if r.contains(.rightShoulder) || r.contains(.rightTrigger) { b.insert(.r) }
            if r.contains(.start) { b.insert(.start) }
            if r.contains(.select) { b.insert(.select) }
            let d = r.union(stickDirs)
            if d.contains(.up) { b.insert(.up) }
            if d.contains(.down) { b.insert(.down) }
            if d.contains(.left) { b.insert(.left) }
            if d.contains(.right) { b.insert(.right) }
            return (b.rawValue, 0, 0)

        case .psp:
            var b: PSPInput = []
            if r.contains(.south) { b.insert(.cross) }
            if r.contains(.east) { b.insert(.circle) }
            if r.contains(.west) { b.insert(.square) }
            if r.contains(.north) { b.insert(.triangle) }
            if r.contains(.leftShoulder) || r.contains(.leftTrigger) { b.insert(.l) }
            if r.contains(.rightShoulder) || r.contains(.rightTrigger) { b.insert(.r) }
            if r.contains(.start) { b.insert(.start) }
            if r.contains(.select) { b.insert(.select) }
            if r.contains(.up) { b.insert(.up) }
            if r.contains(.down) { b.insert(.down) }
            if r.contains(.left) { b.insert(.left) }
            if r.contains(.right) { b.insert(.right) }
            return (b.rawValue, pad.leftStickX, pad.leftStickY)

        case .n64:
            var b: N64Input = []
            if r.contains(.south) { b.insert(.a) }
            if r.contains(.west) { b.insert(.b) }
            // Spare face buttons reach the two most-used C buttons.
            if r.contains(.east) { b.insert(.cDown) }
            if r.contains(.north) { b.insert(.cLeft) }
            if r.contains(.leftTrigger) { b.insert(.z) }
            if r.contains(.leftShoulder) { b.insert(.l) }
            if r.contains(.rightShoulder) || r.contains(.rightTrigger) { b.insert(.r) }
            if r.contains(.start) { b.insert(.start) }
            if r.contains(.up) { b.insert(.dpadUp) }
            if r.contains(.down) { b.insert(.dpadDown) }
            if r.contains(.left) { b.insert(.dpadLeft) }
            if r.contains(.right) { b.insert(.dpadRight) }
            let c = directions(x: pad.rightStickX, y: pad.rightStickY)
            if c.contains(.up) { b.insert(.cUp) }
            if c.contains(.down) { b.insert(.cDown) }
            if c.contains(.left) { b.insert(.cLeft) }
            if c.contains(.right) { b.insert(.cRight) }
            return (b.rawValue, pad.leftStickX, pad.leftStickY)

        case .nes, .snes, .genesis, .atari7800, .ps1:
            var b = retroPadFace(r, for: system)
            if r.contains(.start) { b.insert(.start) }
            if r.contains(.select) { b.insert(.select) }
            let d = r.union(stickDirs)
            if d.contains(.up) { b.insert(.up) }
            if d.contains(.down) { b.insert(.down) }
            if d.contains(.left) { b.insert(.left) }
            if d.contains(.right) { b.insert(.right) }
            return (b.rawValue, 0, 0)
        }
    }

    /// Face and shoulder buttons for the libretro systems, by position on the pad.
    static func retroPadFace(_ r: PadRole, for system: SystemID) -> RetroPadInput {
        var b: RetroPadInput = []
        func on(_ role: PadRole, _ input: RetroPadInput) { if r.contains(role) { b.insert(input) } }
        switch system {
        case .nes:
            on(.east, RetroPadInput.NES.a)
            on(.south, RetroPadInput.NES.b)
            on(.north, RetroPadInput.NES.a)
            on(.west, RetroPadInput.NES.b)
        case .snes:
            on(.east, RetroPadInput.SNES.a)
            on(.south, RetroPadInput.SNES.b)
            on(.north, RetroPadInput.SNES.x)
            on(.west, RetroPadInput.SNES.y)
            on(.leftShoulder, .l); on(.leftTrigger, .l)
            on(.rightShoulder, .r); on(.rightTrigger, .r)
        case .genesis:
            // A B C along the bottom row as on the pad; X Y Z on the shoulders and top button.
            on(.west, RetroPadInput.Genesis.a)
            on(.south, RetroPadInput.Genesis.b)
            on(.east, RetroPadInput.Genesis.c)
            on(.leftShoulder, RetroPadInput.Genesis.x)
            on(.north, RetroPadInput.Genesis.y)
            on(.rightShoulder, RetroPadInput.Genesis.z)
        case .atari7800:
            on(.south, RetroPadInput.Atari7800.button1)
            on(.east, RetroPadInput.Atari7800.button2)
            on(.west, RetroPadInput.Atari7800.button1)
            on(.north, RetroPadInput.Atari7800.button2)
        case .ps1:
            on(.south, RetroPadInput.PS1.cross)
            on(.east, RetroPadInput.PS1.circle)
            on(.west, RetroPadInput.PS1.square)
            on(.north, RetroPadInput.PS1.triangle)
            on(.leftShoulder, RetroPadInput.PS1.l1)
            on(.rightShoulder, RetroPadInput.PS1.r1)
            on(.leftTrigger, RetroPadInput.PS1.l2)
            on(.rightTrigger, RetroPadInput.PS1.r2)
        case .gba, .n64, .nds, .psp:
            break
        }
        return b
    }

    /// Stick → digital directions (8-way, threshold on each axis).
    public static func directions(x: Float, y: Float) -> PadRole {
        var d: PadRole = []
        if y > digitalThreshold { d.insert(.up) }
        if y < -digitalThreshold { d.insert(.down) }
        if x < -digitalThreshold { d.insert(.left) }
        if x > digitalThreshold { d.insert(.right) }
        return d
    }
}

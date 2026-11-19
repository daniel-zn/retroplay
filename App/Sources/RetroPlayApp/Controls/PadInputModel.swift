// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Observation
import RetroPlayCore

/// What the multi-touch surface is holding right now.
struct PadTouchOutput: Equatable, Sendable {
    var buttons: UInt32 = 0
    /// −1…1, Y up-positive.
    var stickX: Float = 0
    var stickY: Float = 0
    var touchX: UInt16 = 0
    var touchY: UInt16 = 0
    var touching = false

    static let idle = PadTouchOutput()
}

/// Merges on-screen touch, physical controllers and keyboard into one
/// `EmulatorInputState` for the core, and exposes held state for the pad visuals.
///
/// Pad visuals observe only `buttons`, `stick` and `releaseCount`, each set only when it
/// changes: a button press re-renders the buttons, not the whole Play screen, and a stick or
/// DS-screen move doesn't re-render the buttons.
@MainActor
@Observable
final class PadInputModel {
    let system: SystemID

    @ObservationIgnored private var touch = PadTouchOutput.idle
    @ObservationIgnored private var physical = PhysicalPadState.neutral
    /// Union of every source, for button highlights.
    private(set) var buttons: UInt32 = 0
    /// Stick position for the on-screen nub (touch wins while a finger is on it).
    private(set) var stick = SIMD2<Float>.zero
    /// Bumped by `releaseAll()` so the touch surface can re-apply fingers still held.
    private(set) var releaseCount = 0

    /// Called with the merged state whenever anything changes.
    @ObservationIgnored var onChange: ((EmulatorInputState) -> Void)?
    @ObservationIgnored private var lastSent = EmulatorInputState.neutral

    init(system: SystemID) {
        self.system = system
    }

    private var physicalMapped: (buttons: UInt32, analogX: Float, analogY: Float) {
        ControllerMapping.map(physical, for: system)
    }

    func isHeld(_ bits: UInt32) -> Bool {
        bits != 0 && buttons & bits == bits
    }

    var state: EmulatorInputState {
        let mapped = physicalMapped
        let useTouchStick = touch.stickX != 0 || touch.stickY != 0
        return EmulatorInputState(
            buttons: touch.buttons | mapped.buttons,
            analogX: useTouchStick ? touch.stickX : mapped.analogX,
            analogY: useTouchStick ? touch.stickY : mapped.analogY,
            touchX: touch.touchX,
            touchY: touch.touchY,
            touching: touch.touching
        )
    }

    func applyTouch(_ output: PadTouchOutput) {
        guard output != touch else { return }
        touch = output
        publish()
    }

    func applyPhysical(_ pad: PhysicalPadState) {
        guard pad != physical else { return }
        physical = pad
        publish()
    }

    /// Drop everything (menu opened, app backgrounded) so nothing stays stuck down.
    func releaseAll() {
        touch = .idle
        physical = .neutral
        releaseCount &+= 1
        publish()
    }

    /// Hold `bits` for `duration` (accessibility / smoke tests).
    func pulse(_ bits: UInt32, duration: Duration = .milliseconds(150)) {
        var down = touch
        down.buttons |= bits
        applyTouch(down)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self else { return }
            var up = self.touch
            up.buttons &= ~bits
            self.applyTouch(up)
        }
    }

    private func publish() {
        let next = state
        if next.buttons != buttons { buttons = next.buttons }
        let nub = SIMD2(next.analogX, next.analogY)
        if nub != stick { stick = nub }
        guard next != lastSent else { return }
        lastSent = next
        onChange?(next)
    }
}

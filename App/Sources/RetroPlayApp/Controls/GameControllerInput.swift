// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import GameController
import Observation
import RetroPlayCore

/// Feeds MFi / Xbox / PlayStation / Switch controllers and hardware keyboards into a
/// `PadInputModel`. Buttons are mapped by position (see `ControllerMapping`).
///
/// Keyboard: arrows = D-pad · Z/X/A/S = south/east/west/north face ·
/// Q/W = L/R · E/R = L2/R2 (N64 Z) · Return = Start · Right Shift / Delete = Select ·
/// I/J/K/L = right stick (N64 C buttons) · Esc = menu.
@available(iOS 18.0, *)
@MainActor
@Observable
final class GameControllerInput {
    private(set) var controllerName: String?
    var hasController: Bool { controllerName != nil }

    @ObservationIgnored var onState: ((PhysicalPadState) -> Void)?
    @ObservationIgnored var onMenu: (() -> Void)?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var gamepadState = PhysicalPadState.neutral
    @ObservationIgnored private var keyboardState = PhysicalPadState.neutral
    @ObservationIgnored private var keyboardRoles: PadRole = []
    @ObservationIgnored private var keyboardRight: Set<GCKeyCode> = []
    /// Home was down on the previous gamepad event; the menu fires on the press edge only.
    @ObservationIgnored private var homeHeld = false

    init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshControllers() }
            })
        }
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshKeyboard() }
            })
        }
        GCController.shouldMonitorBackgroundEvents = false
        refreshControllers()
        refreshKeyboard()
        #if DEBUG
        // Simulator screenshots of the controller layouts: `-RetroPlaySmokeController YES`.
        if UserDefaults.standard.bool(forKey: "RetroPlaySmokeController") {
            controllerName = "Test Controller"
        }
        // Screenshots of a controller coming and going mid-game:
        // `-RetroPlaySmokeControllerToggle <seconds>` connects and disconnects a pretend one.
        let every = UserDefaults.standard.double(forKey: "RetroPlaySmokeControllerToggle")
        if every > 0 {
            Task { @MainActor [weak self] in
                while let self, !self.observers.isEmpty {
                    try? await Task.sleep(for: .seconds(every))
                    self.controllerName = self.controllerName == nil ? "Test Controller" : nil
                    self.gamepadState = .neutral
                    self.publish()
                }
            }
        }
        #endif
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
            controller.microGamepad?.valueChangedHandler = nil
        }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        homeHeld = false
        gamepadState = .neutral
        keyboardState = .neutral
        publish()
    }

    // MARK: Controllers

    private func refreshControllers() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        let current = GCController.current.flatMap { $0.extendedGamepad != nil ? $0 : nil } ?? pads.first
        controllerName = current.map { $0.vendorName ?? "Controller" }
        for pad in pads {
            pad.extendedGamepad?.valueChangedHandler = nil
        }
        guard let current, let gamepad = current.extendedGamepad else {
            // The game carries on: the touch controls fade back in for the player.
            gamepadState = .neutral
            homeHeld = false
            publish()
            return
        }
        // valueChangedHandler fires for every stick and trigger change, so a held Home
        // would toggle the menu many times; only released -> pressed opens it.
        // Home is RetroPlay's pause button; without this iOS keeps it for its own overlay.
        gamepad.buttonHome?.preferredSystemGestureState = .alwaysReceive
        homeHeld = gamepad.buttonHome?.isPressed ?? false
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            let snapshot = Self.read(gamepad)
            let home = gamepad.buttonHome?.isPressed ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                let pressedNow = home && !self.homeHeld
                self.homeHeld = home
                self.gamepadState = snapshot
                self.publish()
                if pressedNow { self.onMenu?() }
            }
        }
        gamepadState = Self.read(gamepad)
        publish()
    }

    private nonisolated static func read(_ g: GCExtendedGamepad) -> PhysicalPadState {
        var roles: PadRole = []
        if g.buttonA.isPressed { roles.insert(.south) }
        if g.buttonB.isPressed { roles.insert(.east) }
        if g.buttonX.isPressed { roles.insert(.west) }
        if g.buttonY.isPressed { roles.insert(.north) }
        if g.leftShoulder.isPressed { roles.insert(.leftShoulder) }
        if g.rightShoulder.isPressed { roles.insert(.rightShoulder) }
        if g.leftTrigger.isPressed { roles.insert(.leftTrigger) }
        if g.rightTrigger.isPressed { roles.insert(.rightTrigger) }
        if g.buttonMenu.isPressed { roles.insert(.start) }
        if g.buttonOptions?.isPressed == true { roles.insert(.select) }
        if g.dpad.up.isPressed { roles.insert(.up) }
        if g.dpad.down.isPressed { roles.insert(.down) }
        if g.dpad.left.isPressed { roles.insert(.left) }
        if g.dpad.right.isPressed { roles.insert(.right) }
        return PhysicalPadState(
            roles: roles,
            leftStickX: g.leftThumbstick.xAxis.value,
            leftStickY: g.leftThumbstick.yAxis.value,
            rightStickX: g.rightThumbstick.xAxis.value,
            rightStickY: g.rightThumbstick.yAxis.value
        )
    }

    // MARK: Keyboard

    private func refreshKeyboard() {
        keyboardRoles = []
        keyboardRight = []
        keyboardState = .neutral
        guard let input = GCKeyboard.coalesced?.keyboardInput else {
            publish()
            return
        }
        input.keyChangedHandler = { [weak self] _, _, key, pressed in
            MainActor.assumeIsolated {
                self?.handleKey(key, pressed: pressed)
            }
        }
        publish()
    }

    private static let keyRoles: [GCKeyCode: PadRole] = [
        .upArrow: .up, .downArrow: .down, .leftArrow: .left, .rightArrow: .right,
        .keyZ: .south, .keyX: .east, .keyA: .west, .keyS: .north,
        .keyQ: .leftShoulder, .keyW: .rightShoulder,
        .keyE: .leftTrigger, .keyR: .rightTrigger,
        .returnOrEnter: .start, .rightShift: .select, .deleteOrBackspace: .select,
    ]

    private static let rightStickKeys: Set<GCKeyCode> = [.keyI, .keyJ, .keyK, .keyL]

    private func handleKey(_ key: GCKeyCode, pressed: Bool) {
        if key == .escape {
            if pressed { onMenu?() }
            return
        }
        if let role = Self.keyRoles[key] {
            if pressed { keyboardRoles.insert(role) } else { keyboardRoles.remove(role) }
        } else if Self.rightStickKeys.contains(key) {
            if pressed { keyboardRight.insert(key) } else { keyboardRight.remove(key) }
        } else {
            return
        }
        var state = PhysicalPadState(roles: keyboardRoles)
        state.rightStickX = (keyboardRight.contains(.keyL) ? 1 : 0) - (keyboardRight.contains(.keyJ) ? 1 : 0)
        state.rightStickY = (keyboardRight.contains(.keyI) ? 1 : 0) - (keyboardRight.contains(.keyK) ? 1 : 0)
        // Arrows double as the analog stick on PSP/N64 so keyboard players can move.
        state.leftStickX = (keyboardRoles.contains(.right) ? 1 : 0) - (keyboardRoles.contains(.left) ? 1 : 0)
        state.leftStickY = (keyboardRoles.contains(.up) ? 1 : 0) - (keyboardRoles.contains(.down) ? 1 : 0)
        keyboardState = state
        publish()
    }

    // MARK: Merge

    private func publish() {
        var merged = gamepadState
        merged.roles.formUnion(keyboardState.roles)
        func pick(_ a: Float, _ b: Float) -> Float { abs(a) >= abs(b) ? a : b }
        merged.leftStickX = pick(gamepadState.leftStickX, keyboardState.leftStickX)
        merged.leftStickY = pick(gamepadState.leftStickY, keyboardState.leftStickY)
        merged.rightStickX = pick(gamepadState.rightStickX, keyboardState.rightStickX)
        merged.rightStickY = pick(gamepadState.rightStickY, keyboardState.rightStickY)
        onState?(merged)
    }
}

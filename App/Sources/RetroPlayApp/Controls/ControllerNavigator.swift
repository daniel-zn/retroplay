// SPDX-License-Identifier: GPL-3.0-or-later
import GameController
import Observation
import SwiftUI

/// A move through the app's own screens with a game controller.
enum ControllerNavCommand: Equatable {
    case up, down, left, right
    /// A (Cross on PlayStation pads).
    case confirm
    /// B (Circle).
    case back
    /// L1 / R1.
    case previousPage, nextPage
}

/// Which screen controller moves go to.
enum ControllerNavContext: Equatable {
    case library
    case pauseMenu
}

/// Drives the library and the pause menu from a game controller. It polls the current
/// controller instead of installing handlers, so the in-game input (`GameControllerInput`)
/// keeps its own. Nothing is sent while a game is running with its menu closed.
@available(iOS 18.0, *)
@MainActor
@Observable
final class ControllerNavigator {
    struct Event: Equatable {
        let command: ControllerNavCommand
        let context: ControllerNavContext
        let id: Int
    }

    /// The newest move; screens react to it with `onChange`.
    private(set) var event: Event?
    /// A controller is connected: screens show where the cursor is.
    private(set) var isConnected = false

    /// The library is on screen with nothing over it.
    var libraryVisible = false
    /// A game is on screen (its own input owns the controller unless the menu is open).
    var playing = false
    var pauseMenuOpen = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pressed: Set<Button> = []
    @ObservationIgnored private var heldDirection: ControllerNavCommand?
    @ObservationIgnored private var nextRepeat: TimeInterval = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private enum Button: Hashable { case a, b, l1, r1 }

    /// Hold a direction: one move, then repeats after this delay, every `repeatInterval`.
    private static let repeatDelay: TimeInterval = 0.35
    private static let repeatInterval: TimeInterval = 0.12

    var context: ControllerNavContext? {
        if pauseMenuOpen { return .pauseMenu }
        if playing { return nil }
        return libraryVisible ? .library : nil
    }

    func start() {
        guard timer == nil else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshConnection() }
            })
        }
        refreshConnection()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #if DEBUG
        playSmokeMoves()
        #endif
    }

    #if DEBUG
    /// Simulator screenshots (no controller there): `-RetroPlaySmokeNav "down,right,a"` plays
    /// these moves, one every 0.4 s, after `-RetroPlaySmokeNavDelay` seconds (default 3).
    private func playSmokeMoves() {
        guard let list = UserDefaults.standard.string(forKey: "RetroPlaySmokeNav") else { return }
        let names: [String: ControllerNavCommand] = [
            "up": .up, "down": .down, "left": .left, "right": .right,
            "a": .confirm, "b": .back, "l1": .previousPage, "r1": .nextPage,
        ]
        let moves = list.split(separator: ",").compactMap { names[$0.trimmingCharacters(in: .whitespaces)] }
        let delay = UserDefaults.standard.object(forKey: "RetroPlaySmokeNavDelay") as? Double ?? 3
        let wantsMenu = UserDefaults.standard.bool(forKey: "RetroPlaySmokeMenu")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            isConnected = true
            // Games boot at their own pace: wait (up to a minute) for the screen the moves are for.
            for _ in 0..<300 where wantsMenu ? context != .pauseMenu : context == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .milliseconds(600))
            for move in moves {
                if let context { send(move, context) } else { NSLog("RP_NAV %@ dropped (no screen takes moves)", "\(move)") }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
    #endif

    private func refreshConnection() {
        isConnected = GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private var hasPad: Bool { GCController.controllers().contains { $0.extendedGamepad != nil } }

    private func poll() {
        guard hasPad,
              let pad = GCController.current?.extendedGamepad
                ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
        else {
            pressed = []
            heldDirection = nil
            return
        }
        guard let context else {
            // Remember what's held, so a button still down when the menu opens doesn't fire.
            pressed = currentButtons(pad)
            heldDirection = direction(pad)
            nextRepeat = .infinity
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let buttons = currentButtons(pad)
        for button in buttons.subtracting(pressed) {
            switch button {
            case .a: send(.confirm, context)
            case .b: send(.back, context)
            case .l1: send(.previousPage, context)
            case .r1: send(.nextPage, context)
            }
        }
        pressed = buttons

        let direction = direction(pad)
        if direction != heldDirection {
            heldDirection = direction
            if let direction {
                send(direction, context)
                nextRepeat = now + Self.repeatDelay
            }
        } else if let direction, now >= nextRepeat {
            send(direction, context)
            nextRepeat = now + Self.repeatInterval
        }
    }

    private func currentButtons(_ pad: GCExtendedGamepad) -> Set<Button> {
        var buttons: Set<Button> = []
        if pad.buttonA.isPressed { buttons.insert(.a) }
        if pad.buttonB.isPressed { buttons.insert(.b) }
        if pad.leftShoulder.isPressed { buttons.insert(.l1) }
        if pad.rightShoulder.isPressed { buttons.insert(.r1) }
        return buttons
    }

    /// D-pad first, else the left stick past half tilt; the stronger axis wins.
    private func direction(_ pad: GCExtendedGamepad) -> ControllerNavCommand? {
        let dpad = pad.dpad
        if dpad.up.isPressed { return .up }
        if dpad.down.isPressed { return .down }
        if dpad.left.isPressed { return .left }
        if dpad.right.isPressed { return .right }
        let x = pad.leftThumbstick.xAxis.value, y = pad.leftThumbstick.yAxis.value
        guard max(abs(x), abs(y)) > 0.5 else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .up : .down
    }

    private func send(_ command: ControllerNavCommand, _ context: ControllerNavContext) {
        nextID += 1
        event = Event(command: command, context: context, id: nextID)
    }
}

extension View {
    /// The controller cursor: a ring around the focused control.
    func controllerFocusRing(_ focused: Bool, cornerRadius: CGFloat = 14) -> some View {
        overlay {
            if focused {
                RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .strokeBorder(RetroPlayTheme.accent, lineWidth: 3)
                    .padding(-5)
                    .allowsHitTesting(false)
            }
        }
    }
}

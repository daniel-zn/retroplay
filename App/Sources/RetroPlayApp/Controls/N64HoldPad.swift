import SwiftUI
import RetroPlayCore

typealias N64HeldHandler = @MainActor @Sendable (N64Input, Bool) -> Void

@available(iOS 18.0, *)
struct N64HoldPadButton: View {
    let title: String
    let bit: N64Input
    let isHeld: Bool
    let diameter: CGFloat
    var fill: Color = PadPalette.N64.chassisDark
    var ink: Color = PadPalette.N64.inkLight
    var accessibilityName: String? = nil
    let setHeld: N64HeldHandler

    init(
        title: String,
        bit: N64Input,
        isHeld: Bool,
        diameter: CGFloat = 52,
        fill: Color = PadPalette.N64.chassisDark,
        ink: Color = PadPalette.N64.inkLight,
        accessibilityName: String? = nil,
        setHeld: @escaping N64HeldHandler
    ) {
        self.title = title
        self.bit = bit
        self.isHeld = isHeld
        self.diameter = diameter
        self.fill = fill
        self.ink = ink
        self.accessibilityName = accessibilityName
        self.setHeld = setHeld
    }

    var body: some View {
        PadFaceButton(
            title: title,
            isHeld: isHeld,
            diameter: diameter,
            fill: fill,
            ink: ink,
            accessibilityName: accessibilityName,
            onHeld: { setHeld(bit, $0) }
        )
    }
}

@available(iOS 18.0, *)
struct N64HoldPadCapsule: View {
    let title: String
    let bit: N64Input
    let isHeld: Bool
    var fill: Color = PadPalette.N64.start
    var ink: Color = PadPalette.N64.inkLight
    let setHeld: N64HeldHandler

    var body: some View {
        PadOvalButton(
            title: title,
            isHeld: isHeld,
            minWidth: 64,
            minHeight: 44,
            fill: fill,
            ink: ink,
            onHeld: { setHeld(bit, $0) }
        )
    }
}

@available(iOS 18.0, *)
struct N64DPadView: View {
    let held: N64Input
    let arm: CGFloat
    let setHeld: N64HeldHandler

    init(held: N64Input, arm: CGFloat = 46, setHeld: @escaping N64HeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        CrossDPad(
            size: arm * 2.45,
            armThickness: max(44, arm),
            isUp: held.contains(.dpadUp),
            isDown: held.contains(.dpadDown),
            isLeft: held.contains(.dpadLeft),
            isRight: held.contains(.dpadRight),
            fill: PadPalette.N64.dpad,
            heldFill: PadPalette.N64.chassisDark,
            onChange: { up, down, left, right in
                setHeld(.dpadUp, up)
                setHeld(.dpadDown, down)
                setHeld(.dpadLeft, left)
                setHeld(.dpadRight, right)
            }
        )
    }
}

/// C-button diamond (yellow). Labels are arrows; accessibility names keep the C prefix.
@available(iOS 18.0, *)
struct N64CCluster: View {
    let held: N64Input
    let diameter: CGFloat
    let setHeld: N64HeldHandler

    private var reach: CGFloat { diameter * 0.82 }
    private var side: CGFloat { reach * 2 + diameter + 4 }

    var body: some View {
        ZStack {
            cButton("▲", bit: .cUp, name: "C Up", x: 0, y: -reach)
            cButton("▶", bit: .cRight, name: "C Right", x: reach, y: 0)
            cButton("▼", bit: .cDown, name: "C Down", x: 0, y: reach)
            cButton("◀", bit: .cLeft, name: "C Left", x: -reach, y: 0)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("C buttons")
    }

    private func cButton(_ title: String, bit: N64Input, name: String, x: CGFloat, y: CGFloat) -> some View {
        N64HoldPadButton(
            title: title,
            bit: bit,
            isHeld: held.contains(bit),
            diameter: diameter,
            fill: PadPalette.N64.c,
            ink: PadPalette.N64.inkDark,
            accessibilityName: name,
            setHeld: setHeld
        )
        .offset(x: x, y: y)
    }
}

/// Analog Control Stick: octagonal well + drag nub → `N64AnalogStick` (±80).
@available(iOS 18.0, *)
struct N64StickPad: View {
    let stick: N64AnalogStick
    let setStick: @MainActor @Sendable (N64AnalogStick) -> Void
    var wellSize: CGFloat = 92

    var body: some View {
        AnalogStickWell(
            wellSize: wellSize,
            x: CGFloat(stick.x) / 80,
            y: CGFloat(stick.y) / 80,
            wellFill: PadPalette.N64.stickWell,
            nubFill: PadPalette.N64.stickNub,
            accessibilityName: "Control Stick",
            onChange: { x, y in setStick(N64AnalogStick(x: x, y: y)) }
        )
    }
}

import SwiftUI
import RetroPlayCore

typealias NDSHeldHandler = @MainActor @Sendable (NDSInput, Bool) -> Void

@available(iOS 18.0, *)
struct NDSHoldPadButton: View {
    let title: String
    let bit: NDSInput
    let isHeld: Bool
    let diameter: CGFloat
    var fill: Color = PadPalette.NDS.dpad
    var ink: Color = PadPalette.NDS.ink
    let setHeld: NDSHeldHandler

    init(
        title: String,
        bit: NDSInput,
        isHeld: Bool,
        diameter: CGFloat = 52,
        fill: Color = PadPalette.NDS.dpad,
        ink: Color = PadPalette.NDS.ink,
        setHeld: @escaping NDSHeldHandler
    ) {
        self.title = title
        self.bit = bit
        self.isHeld = isHeld
        self.diameter = diameter
        self.fill = fill
        self.ink = ink
        self.setHeld = setHeld
    }

    var body: some View {
        PadFaceButton(
            title: title,
            isHeld: isHeld,
            diameter: diameter,
            fill: fill,
            ink: ink,
            onHeld: { setHeld(bit, $0) }
        )
    }
}

@available(iOS 18.0, *)
struct NDSHoldPadCapsule: View {
    let title: String
    let bit: NDSInput
    let isHeld: Bool
    let setHeld: NDSHeldHandler

    var body: some View {
        PadOvalButton(
            title: title,
            isHeld: isHeld,
            minWidth: 58,
            minHeight: 40,
            fill: PadPalette.NDS.shoulder,
            ink: PadPalette.NDS.ink,
            onHeld: { setHeld(bit, $0) }
        )
    }
}

@available(iOS 18.0, *)
struct NDSDPadView: View {
    let held: NDSInput
    let arm: CGFloat
    let setHeld: NDSHeldHandler

    init(held: NDSInput, arm: CGFloat = 48, setHeld: @escaping NDSHeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        CrossDPad(
            size: arm * 2.4,
            armThickness: max(44, arm),
            isUp: held.contains(.up),
            isDown: held.contains(.down),
            isLeft: held.contains(.left),
            isRight: held.contains(.right),
            fill: PadPalette.NDS.dpad,
            heldFill: PadPalette.NDS.shoulder,
            onChange: { up, down, left, right in
                setHeld(.up, up)
                setHeld(.down, down)
                setHeld(.left, left)
                setHeld(.right, right)
            }
        )
    }
}

/// Face diamond: X top, A right, B bottom, Y left (DS convention).
@available(iOS 18.0, *)
struct NDSFaceCluster: View {
    let held: NDSInput
    let diameter: CGFloat
    let setHeld: NDSHeldHandler

    private var reach: CGFloat { diameter * 0.82 }
    private var side: CGFloat { reach * 2 + diameter + 4 }

    var body: some View {
        ZStack {
            NDSHoldPadButton(
                title: "X",
                bit: .x,
                isHeld: held.contains(.x),
                diameter: diameter,
                fill: PadPalette.NDS.x,
                setHeld: setHeld
            )
            .offset(x: 0, y: -reach)
            NDSHoldPadButton(
                title: "A",
                bit: .a,
                isHeld: held.contains(.a),
                diameter: diameter,
                fill: PadPalette.NDS.a,
                setHeld: setHeld
            )
            .offset(x: reach, y: 0)
            NDSHoldPadButton(
                title: "B",
                bit: .b,
                isHeld: held.contains(.b),
                diameter: diameter,
                fill: PadPalette.NDS.b,
                ink: PadPalette.NDS.inkDark,
                setHeld: setHeld
            )
            .offset(x: 0, y: reach)
            NDSHoldPadButton(
                title: "Y",
                bit: .y,
                isHeld: held.contains(.y),
                diameter: diameter,
                fill: PadPalette.NDS.y,
                setHeld: setHeld
            )
            .offset(x: -reach, y: 0)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Face buttons")
    }
}

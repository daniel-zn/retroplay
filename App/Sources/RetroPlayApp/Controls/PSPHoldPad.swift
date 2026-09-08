import SwiftUI
import RetroPlayCore

typealias PSPHeldHandler = @MainActor @Sendable (PSPInput, Bool) -> Void

@available(iOS 18.0, *)
struct PSPHoldPadButton: View {
    let title: String
    let bit: PSPInput
    let isHeld: Bool
    let diameter: CGFloat
    var fill: Color = PadPalette.PSP.face
    var ink: Color = PadPalette.PSP.ink
    let setHeld: PSPHeldHandler

    init(
        title: String,
        bit: PSPInput,
        isHeld: Bool,
        diameter: CGFloat = 56,
        fill: Color = PadPalette.PSP.face,
        ink: Color = PadPalette.PSP.ink,
        setHeld: @escaping PSPHeldHandler
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
struct PSPHoldPadCapsule: View {
    let title: String
    let bit: PSPInput
    let isHeld: Bool
    var fill: Color = PadPalette.PSP.silver
    var ink: Color = PadPalette.PSP.chassis
    let setHeld: PSPHeldHandler

    var body: some View {
        PadOvalButton(
            title: title,
            isHeld: isHeld,
            minWidth: 64,
            minHeight: 40,
            fill: fill,
            ink: ink,
            onHeld: { setHeld(bit, $0) }
        )
    }
}

@available(iOS 18.0, *)
struct PSPDPadView: View {
    let held: PSPInput
    let arm: CGFloat
    let setHeld: PSPHeldHandler

    init(held: PSPInput, arm: CGFloat = 52, setHeld: @escaping PSPHeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        CrossDPad(
            size: arm * 2.45,
            armThickness: max(44, arm),
            isUp: held.contains(.up),
            isDown: held.contains(.down),
            isLeft: held.contains(.left),
            isRight: held.contains(.right),
            fill: PadPalette.PSP.dpad,
            heldFill: PadPalette.PSP.nub,
            onChange: { up, down, left, right in
                setHeld(.up, up)
                setHeld(.down, down)
                setHeld(.left, left)
                setHeld(.right, right)
            }
        )
    }
}

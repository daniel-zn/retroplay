import SwiftUI
import RetroPlayCore

/// Plus-shaped D-pad. Diagonals = two bits via `PadHitTesting.dpad`.
@available(iOS 18.0, *)
struct DPadView: View {
    let held: GBAInput
    let arm: CGFloat
    let setHeld: GBAHeldHandler

    init(held: GBAInput, arm: CGFloat = 52, setHeld: @escaping GBAHeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        CrossDPad(
            size: arm * 2.55,
            armThickness: max(44, arm),
            isUp: held.contains(.up),
            isDown: held.contains(.down),
            isLeft: held.contains(.left),
            isRight: held.contains(.right),
            fill: PadPalette.GBA.dpad,
            heldFill: PadPalette.GBA.dpadHeld,
            onChange: { up, down, left, right in
                setHeld(.up, up)
                setHeld(.down, down)
                setHeld(.left, left)
                setHeld(.right, right)
            }
        )
    }
}

import SwiftUI
import RetroPlayCore

/// Cross D-pad with ≥44 pt arms. Four-way for GBA (diagonals = two bits held).
@available(iOS 18.0, *)
struct DPadView: View {
    let held: GBAInput
    let arm: CGFloat
    let setHeld: (GBAInput, Bool) -> Void

    init(held: GBAInput, arm: CGFloat = 52, setHeld: @escaping (GBAInput, Bool) -> Void) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        let gap: CGFloat = 4
        VStack(spacing: gap) {
            HoldPadButton(title: "▲", bit: .up, isHeld: held.contains(.up), diameter: arm, setHeld: setHeld)
            HStack(spacing: gap) {
                HoldPadButton(title: "◀", bit: .left, isHeld: held.contains(.left), diameter: arm, setHeld: setHeld)
                Color.clear.frame(width: arm, height: arm)
                HoldPadButton(title: "▶", bit: .right, isHeld: held.contains(.right), diameter: arm, setHeld: setHeld)
            }
            HoldPadButton(title: "▼", bit: .down, isHeld: held.contains(.down), diameter: arm, setHeld: setHeld)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("D-pad")
    }
}

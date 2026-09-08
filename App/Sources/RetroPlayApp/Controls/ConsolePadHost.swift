import SwiftUI
import RetroPlayCore

/// Picks the on-screen pad for a system.
@available(iOS 18.0, *)
struct ConsolePadHost: View {
    enum Orientation {
        case portrait
        case landscape
    }

    let systemID: SystemID
    let orientation: Orientation
    let gbaHeld: GBAInput
    let setGBAHeld: GBAHeldHandler
    let pspHeld: PSPInput
    let setPSPHeld: PSPHeldHandler
    let n64Held: N64Input
    let setN64Held: N64HeldHandler
    let n64Stick: N64AnalogStick
    let setN64Stick: @MainActor @Sendable (N64AnalogStick) -> Void
    let ndsHeld: NDSInput
    let setNDSHeld: NDSHeldHandler
    var onNDSTouch: (@MainActor @Sendable (NDSTouch) -> Void)? = nil

    var body: some View {
        switch systemID {
        case .gba:
            GBAFamilyPadView(
                orientation: orientation == .portrait ? .portrait : .landscape,
                held: gbaHeld,
                setHeld: setGBAHeld
            )
        case .psp:
            PSPFamilyPadView(
                orientation: orientation == .portrait ? .portrait : .landscape,
                held: pspHeld,
                setHeld: setPSPHeld
            )
        case .n64:
            N64FamilyPadView(
                orientation: orientation == .portrait ? .portrait : .landscape,
                held: n64Held,
                setHeld: setN64Held,
                stick: n64Stick,
                setStick: setN64Stick
            )
        case .nds:
            NDSFamilyPadView(
                orientation: orientation == .portrait ? .portrait : .landscape,
                held: ndsHeld,
                setHeld: setNDSHeld,
                onTouch: onNDSTouch
            )
        }
    }
}

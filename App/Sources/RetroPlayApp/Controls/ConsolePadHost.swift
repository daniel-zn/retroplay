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
        case .n64, .nds:
            EmptyView()
        }
    }
}

import SwiftUI
import RetroPlayCore

/// Picks the on-screen pad for a system. GBA uses the GB-family layout;
/// other P0 systems are empty stubs until their pads land.
@available(iOS 18.0, *)
struct ConsolePadHost: View {
    let systemID: SystemID
    let orientation: GBAFamilyPadView.Orientation
    let held: GBAInput
    let setHeld: (GBAInput, Bool) -> Void

    var body: some View {
        switch systemID {
        case .gba:
            GBAFamilyPadView(orientation: orientation, held: held, setHeld: setHeld)
        case .n64, .nds, .psp:
            // Stub hook: dedicated layouts later (see docs/CONTROLS-GBA.md).
            EmptyView()
        }
    }
}

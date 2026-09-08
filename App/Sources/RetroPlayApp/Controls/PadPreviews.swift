import SwiftUI
import RetroPlayCore

@available(iOS 18.0, *)
#Preview("GBA portrait") {
    GBAFamilyPadView(orientation: .portrait, held: [.a, .up], setHeld: { _, _ in })
        .padding()
        .background(Color.black)
}

@available(iOS 18.0, *)
#Preview("N64 portrait") {
    N64FamilyPadView(
        orientation: .portrait,
        held: [.a, .cUp],
        setHeld: { _, _ in },
        stick: N64AnalogStick(x: 40, y: 20),
        setStick: { _ in }
    )
    .padding()
    .background(Color.black)
}

@available(iOS 18.0, *)
#Preview("NDS portrait") {
    NDSFamilyPadView(orientation: .portrait, held: [.x, .left], setHeld: { _, _ in })
        .padding()
        .background(Color.black)
}

@available(iOS 18.0, *)
#Preview("PSP portrait") {
    PSPFamilyPadView(orientation: .portrait, held: [.cross, .right], setHeld: { _, _ in })
        .padding()
        .background(Color.black)
}

import SwiftUI
import RetroPlayCore

typealias GBAHeldHandler = @MainActor @Sendable (GBAInput, Bool) -> Void

/// Hold-to-press circular face button (GBA bits). Styled via `PadFaceButton`.
@available(iOS 18.0, *)
struct HoldPadButton: View {
    let title: String
    let bit: GBAInput
    let isHeld: Bool
    let diameter: CGFloat
    var fill: Color = PadPalette.GBA.face
    var ink: Color = PadPalette.GBA.ink
    let setHeld: GBAHeldHandler

    init(
        title: String,
        bit: GBAInput,
        isHeld: Bool,
        diameter: CGFloat = 56,
        fill: Color = PadPalette.GBA.face,
        ink: Color = PadPalette.GBA.ink,
        setHeld: @escaping GBAHeldHandler
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
            onHeld: { down in setHeld(bit, down) }
        )
    }
}

/// Capsule hold button for Start / Select (and similar secondary keys).
@available(iOS 18.0, *)
struct HoldPadCapsule: View {
    let title: String
    let bit: GBAInput
    let isHeld: Bool
    var rotation: Angle = .zero
    var fill: Color = PadPalette.GBA.startSelect
    var ink: Color = PadPalette.GBA.ink
    let setHeld: GBAHeldHandler

    var body: some View {
        PadOvalButton(
            title: title,
            isHeld: isHeld,
            minWidth: 64,
            minHeight: 44,
            rotation: rotation,
            fill: fill,
            ink: ink,
            onHeld: { down in setHeld(bit, down) }
        )
    }
}

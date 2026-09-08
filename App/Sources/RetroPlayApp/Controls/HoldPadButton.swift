import SwiftUI
import RetroPlayCore

/// Hold-to-press pad control. Uses a drag gesture (min distance 0) so the bit stays
/// set while the finger is down, matching emulator key semantics.
@available(iOS 18.0, *)
struct HoldPadButton: View {
    let title: String
    let bit: GBAInput
    let isHeld: Bool
    let diameter: CGFloat
    let setHeld: (GBAInput, Bool) -> Void

    init(
        title: String,
        bit: GBAInput,
        isHeld: Bool,
        diameter: CGFloat = 56,
        setHeld: @escaping (GBAInput, Bool) -> Void
    ) {
        self.title = title
        self.bit = bit
        self.isHeld = isHeld
        self.diameter = diameter
        self.setHeld = setHeld
    }

    var body: some View {
        Text(title)
            .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(isHeld ? 1.0 : 0.82)
            }
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(isHeld ? 0.45 : 0.22), lineWidth: isHeld ? 2 : 1)
            }
            .scaleEffect(isHeld ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .contentShape(Circle())
            .gesture(holdGesture)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in setHeld(bit, true) }
            .onEnded { _ in setHeld(bit, false) }
    }
}

/// Capsule hold button for Start / Select (and similar secondary keys).
@available(iOS 18.0, *)
struct HoldPadCapsule: View {
    let title: String
    let bit: GBAInput
    let isHeld: Bool
    let setHeld: (GBAInput, Bool) -> Void

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minWidth: 72, minHeight: 44)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(isHeld ? 1.0 : 0.82)
            }
            .overlay {
                Capsule()
                    .strokeBorder(.primary.opacity(isHeld ? 0.4 : 0.2), lineWidth: 1)
            }
            .scaleEffect(isHeld ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setHeld(bit, true) }
                    .onEnded { _ in setHeld(bit, false) }
            )
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}

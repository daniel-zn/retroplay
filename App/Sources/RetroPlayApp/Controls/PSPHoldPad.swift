import SwiftUI
import RetroPlayCore

typealias PSPHeldHandler = @MainActor @Sendable (PSPInput, Bool) -> Void

/// Hold-to-press circular button for PSP (same gesture model as GBA).
@available(iOS 18.0, *)
struct PSPHoldPadButton: View {
    let title: String
    let bit: PSPInput
    let isHeld: Bool
    let diameter: CGFloat
    let setHeld: PSPHeldHandler

    init(
        title: String,
        bit: PSPInput,
        isHeld: Bool,
        diameter: CGFloat = 56,
        setHeld: @escaping PSPHeldHandler
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setHeld(bit, true) }
                    .onEnded { _ in setHeld(bit, false) }
            )
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}

@available(iOS 18.0, *)
struct PSPHoldPadCapsule: View {
    let title: String
    let bit: PSPInput
    let isHeld: Bool
    let setHeld: PSPHeldHandler

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
        let gap: CGFloat = 4
        VStack(spacing: gap) {
            PSPHoldPadButton(title: "▲", bit: .up, isHeld: held.contains(.up), diameter: arm, setHeld: setHeld)
            HStack(spacing: gap) {
                PSPHoldPadButton(title: "◀", bit: .left, isHeld: held.contains(.left), diameter: arm, setHeld: setHeld)
                Color.clear.frame(width: arm, height: arm)
                PSPHoldPadButton(title: "▶", bit: .right, isHeld: held.contains(.right), diameter: arm, setHeld: setHeld)
            }
            PSPHoldPadButton(title: "▼", bit: .down, isHeld: held.contains(.down), diameter: arm, setHeld: setHeld)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("D-pad")
    }
}

import SwiftUI
import RetroPlayCore

typealias NDSHeldHandler = @MainActor @Sendable (NDSInput, Bool) -> Void

@available(iOS 18.0, *)
struct NDSHoldPadButton: View {
    let title: String
    let bit: NDSInput
    let isHeld: Bool
    let diameter: CGFloat
    let setHeld: NDSHeldHandler

    init(
        title: String,
        bit: NDSInput,
        isHeld: Bool,
        diameter: CGFloat = 52,
        setHeld: @escaping NDSHeldHandler
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
struct NDSHoldPadCapsule: View {
    let title: String
    let bit: NDSInput
    let isHeld: Bool
    let setHeld: NDSHeldHandler

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minWidth: 72, minHeight: 40)
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
struct NDSDPadView: View {
    let held: NDSInput
    let arm: CGFloat
    let setHeld: NDSHeldHandler

    init(held: NDSInput, arm: CGFloat = 48, setHeld: @escaping NDSHeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        let gap: CGFloat = 4
        VStack(spacing: gap) {
            NDSHoldPadButton(title: "▲", bit: .up, isHeld: held.contains(.up), diameter: arm, setHeld: setHeld)
            HStack(spacing: gap) {
                NDSHoldPadButton(title: "◀", bit: .left, isHeld: held.contains(.left), diameter: arm, setHeld: setHeld)
                Color.clear.frame(width: arm, height: arm)
                NDSHoldPadButton(title: "▶", bit: .right, isHeld: held.contains(.right), diameter: arm, setHeld: setHeld)
            }
            NDSHoldPadButton(title: "▼", bit: .down, isHeld: held.contains(.down), diameter: arm, setHeld: setHeld)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("D-pad")
    }
}

/// Face diamond: X top, A right, B bottom, Y left (DS convention).
@available(iOS 18.0, *)
struct NDSFaceCluster: View {
    let held: NDSInput
    let diameter: CGFloat
    let setHeld: NDSHeldHandler

    private var reach: CGFloat { diameter * 0.82 }
    private var side: CGFloat { reach * 2 + diameter + 4 }

    var body: some View {
        ZStack {
            NDSHoldPadButton(title: "X", bit: .x, isHeld: held.contains(.x), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: -reach)
            NDSHoldPadButton(title: "A", bit: .a, isHeld: held.contains(.a), diameter: diameter, setHeld: setHeld)
                .offset(x: reach, y: 0)
            NDSHoldPadButton(title: "B", bit: .b, isHeld: held.contains(.b), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: reach)
            NDSHoldPadButton(title: "Y", bit: .y, isHeld: held.contains(.y), diameter: diameter, setHeld: setHeld)
                .offset(x: -reach, y: 0)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Face buttons")
    }
}

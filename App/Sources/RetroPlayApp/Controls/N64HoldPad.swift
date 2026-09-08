import SwiftUI
import RetroPlayCore

typealias N64HeldHandler = @MainActor @Sendable (N64Input, Bool) -> Void

/// Hold-to-press circular button for N64.
@available(iOS 18.0, *)
struct N64HoldPadButton: View {
    let title: String
    let bit: N64Input
    let isHeld: Bool
    let diameter: CGFloat
    let setHeld: N64HeldHandler

    init(
        title: String,
        bit: N64Input,
        isHeld: Bool,
        diameter: CGFloat = 52,
        setHeld: @escaping N64HeldHandler
    ) {
        self.title = title
        self.bit = bit
        self.isHeld = isHeld
        self.diameter = diameter
        self.setHeld = setHeld
    }

    var body: some View {
        Text(title)
            .font(.system(size: diameter * 0.30, weight: .semibold, design: .rounded))
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
struct N64HoldPadCapsule: View {
    let title: String
    let bit: N64Input
    let isHeld: Bool
    let setHeld: N64HeldHandler

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minWidth: 64, minHeight: 40)
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
struct N64DPadView: View {
    let held: N64Input
    let arm: CGFloat
    let setHeld: N64HeldHandler

    init(held: N64Input, arm: CGFloat = 46, setHeld: @escaping N64HeldHandler) {
        self.held = held
        self.arm = arm
        self.setHeld = setHeld
    }

    var body: some View {
        let gap: CGFloat = 4
        VStack(spacing: gap) {
            N64HoldPadButton(title: "▲", bit: .dpadUp, isHeld: held.contains(.dpadUp), diameter: arm, setHeld: setHeld)
            HStack(spacing: gap) {
                N64HoldPadButton(title: "◀", bit: .dpadLeft, isHeld: held.contains(.dpadLeft), diameter: arm, setHeld: setHeld)
                Color.clear.frame(width: arm, height: arm)
                N64HoldPadButton(title: "▶", bit: .dpadRight, isHeld: held.contains(.dpadRight), diameter: arm, setHeld: setHeld)
            }
            N64HoldPadButton(title: "▼", bit: .dpadDown, isHeld: held.contains(.dpadDown), diameter: arm, setHeld: setHeld)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("D-pad")
    }
}

/// C-button diamond (↑←↓→ mapped to cUp/cLeft/cDown/cRight).
@available(iOS 18.0, *)
struct N64CCluster: View {
    let held: N64Input
    let diameter: CGFloat
    let setHeld: N64HeldHandler

    private var reach: CGFloat { diameter * 0.78 }

    private var side: CGFloat { reach * 2 + diameter + 4 }

    var body: some View {
        ZStack {
            N64HoldPadButton(title: "C▲", bit: .cUp, isHeld: held.contains(.cUp), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: -reach)
            N64HoldPadButton(title: "C▶", bit: .cRight, isHeld: held.contains(.cRight), diameter: diameter, setHeld: setHeld)
                .offset(x: reach, y: 0)
            N64HoldPadButton(title: "C▼", bit: .cDown, isHeld: held.contains(.cDown), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: reach)
            N64HoldPadButton(title: "C◀", bit: .cLeft, isHeld: held.contains(.cLeft), diameter: diameter, setHeld: setHeld)
                .offset(x: -reach, y: 0)
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("C buttons")
    }
}

/// Crude stick: eight-way digital → N64AnalogStick (±80).
@available(iOS 18.0, *)
struct N64StickPad: View {
    let stick: N64AnalogStick
    let setStick: @MainActor @Sendable (N64AnalogStick) -> Void
    let arm: CGFloat

    private let magnitude: Int8 = 80

    var body: some View {
        let gap: CGFloat = 3
        VStack(spacing: gap) {
            stickButton(title: "▲", value: N64AnalogStick(x: 0, y: magnitude))
            HStack(spacing: gap) {
                stickButton(title: "◀", value: N64AnalogStick(x: -magnitude, y: 0))
                Color.clear.frame(width: arm * 0.7, height: arm * 0.7)
                stickButton(title: "▶", value: N64AnalogStick(x: magnitude, y: 0))
            }
            stickButton(title: "▼", value: N64AnalogStick(x: 0, y: -magnitude))
        }
        .accessibilityLabel("Analog stick")
    }

    private func stickButton(title: String, value: N64AnalogStick) -> some View {
        let active = stick.x == value.x && stick.y == value.y
        return Text(title)
            .font(.system(size: arm * 0.28, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: arm * 0.85, height: arm * 0.85)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(active ? 1.0 : 0.75)
            }
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(active ? 0.45 : 0.18), lineWidth: active ? 2 : 1)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setStick(value) }
                    .onEnded { _ in setStick(.zero) }
            )
    }
}

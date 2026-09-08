import SwiftUI
import RetroPlayCore

/// Shared hold-to-press gesture used by every console pad.
@available(iOS 18.0, *)
enum PadHold {
    static func drag(_ onHeld: @escaping @MainActor @Sendable (Bool) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onHeld(true) }
            .onEnded { _ in onHeld(false) }
    }
}

/// Hardware-inspired palettes. Layout accuracy first; tints are recognition cues, not skins.
@available(iOS 18.0, *)
enum PadPalette {
    enum GBA {
        static let chassis = Color(red: 0.36, green: 0.32, blue: 0.62)
        static let chassisStroke = Color(red: 0.55, green: 0.50, blue: 0.82)
        static let dpad = Color(red: 0.16, green: 0.14, blue: 0.22)
        static let dpadHeld = Color(red: 0.28, green: 0.24, blue: 0.40)
        static let face = Color(red: 0.42, green: 0.34, blue: 0.72)
        static let faceA = Color(red: 0.58, green: 0.42, blue: 0.88)
        static let ink = Color.white.opacity(0.92)
        static let startSelect = Color(red: 0.22, green: 0.18, blue: 0.34)
        static let shoulder = Color(red: 0.28, green: 0.24, blue: 0.46)
    }

    enum N64 {
        static let chassis = Color(red: 0.58, green: 0.58, blue: 0.60)
        static let chassisDark = Color(red: 0.42, green: 0.42, blue: 0.45)
        static let chassisStroke = Color.white.opacity(0.18)
        static let dpad = Color(red: 0.28, green: 0.28, blue: 0.30)
        static let stickWell = Color(red: 0.22, green: 0.22, blue: 0.24)
        static let stickNub = Color(red: 0.14, green: 0.14, blue: 0.16)
        static let a = Color(red: 0.18, green: 0.42, blue: 0.86)
        static let b = Color(red: 0.22, green: 0.70, blue: 0.36)
        static let c = Color(red: 0.96, green: 0.82, blue: 0.18)
        static let start = Color(red: 0.84, green: 0.18, blue: 0.20)
        static let z = Color(red: 0.16, green: 0.16, blue: 0.18)
        static let shoulder = Color(red: 0.48, green: 0.48, blue: 0.50)
        static let inkDark = Color(red: 0.12, green: 0.12, blue: 0.14)
        static let inkLight = Color.white.opacity(0.95)
    }

    enum NDS {
        static let chassis = Color(red: 0.30, green: 0.32, blue: 0.36)
        static let chassisStroke = Color(red: 0.62, green: 0.64, blue: 0.68)
        static let dpad = Color(red: 0.18, green: 0.18, blue: 0.20)
        static let a = Color(red: 0.82, green: 0.28, blue: 0.32)
        static let b = Color(red: 0.88, green: 0.72, blue: 0.22)
        static let x = Color(red: 0.32, green: 0.52, blue: 0.88)
        static let y = Color(red: 0.28, green: 0.68, blue: 0.42)
        static let shoulder = Color(red: 0.42, green: 0.44, blue: 0.48)
        static let touchBezel = Color(red: 0.52, green: 0.54, blue: 0.58)
        static let touchGlass = Color(red: 0.08, green: 0.09, blue: 0.11)
        static let ink = Color.white.opacity(0.94)
        static let inkDark = Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    enum PSP {
        static let chassis = Color(red: 0.08, green: 0.08, blue: 0.09)
        static let chassisStroke = Color(red: 0.72, green: 0.74, blue: 0.78)
        static let dpad = Color(red: 0.18, green: 0.18, blue: 0.20)
        static let face = Color(red: 0.12, green: 0.12, blue: 0.13)
        static let triangle = Color(red: 0.28, green: 0.78, blue: 0.62)
        static let circle = Color(red: 0.90, green: 0.30, blue: 0.34)
        static let cross = Color(red: 0.38, green: 0.56, blue: 0.96)
        static let square = Color(red: 0.92, green: 0.48, blue: 0.72)
        static let silver = Color(red: 0.74, green: 0.76, blue: 0.80)
        static let nub = Color(red: 0.32, green: 0.32, blue: 0.34)
        static let ink = Color.white.opacity(0.92)
    }
}

// MARK: - Shapes

@available(iOS 18.0, *)
struct PlusShape: Shape {
    var armThickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(armThickness, rect.width, rect.height)
        let x0 = rect.midX - t / 2
        let y0 = rect.midY - t / 2
        let radius = t * 0.22
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: x0, y: rect.minY, width: t, height: rect.height),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: y0, width: rect.width, height: t),
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }
}

/// Regular octagon with flats on the cardinals (N64 Control Stick gate).
@available(iOS 18.0, *)
struct RegularOctagon: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * (.pi / 4) - .pi / 8
            let point = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Buttons

@available(iOS 18.0, *)
struct PadFaceButton: View {
    let title: String
    let isHeld: Bool
    var diameter: CGFloat = 52
    var fill: Color
    var ink: Color
    var stroke: Color = Color.white.opacity(0.22)
    var accessibilityName: String? = nil
    let onHeld: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Text(title)
            .font(.system(size: max(11, diameter * 0.34), weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(fill)
                    .shadow(color: .black.opacity(isHeld ? 0.08 : 0.28), radius: isHeld ? 1 : 3, y: isHeld ? 0 : 2)
            }
            .overlay {
                Circle()
                    .strokeBorder(stroke.opacity(isHeld ? 0.9 : 0.7), lineWidth: isHeld ? 2 : 1)
            }
            .scaleEffect(isHeld ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .contentShape(Circle())
            .gesture(PadHold.drag(onHeld))
            .accessibilityLabel(accessibilityName ?? title)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isHeld ? "Held" : "Released")
    }
}

@available(iOS 18.0, *)
struct PadShoulderButton: View {
    let title: String
    let isHeld: Bool
    var width: CGFloat = 76
    var height: CGFloat = 44
    var fill: Color
    var ink: Color
    let onHeld: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: width, height: height)
            .background {
                Capsule()
                    .fill(fill)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(isHeld ? 0.45 : 0.18), lineWidth: isHeld ? 2 : 1)
            }
            .scaleEffect(isHeld ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .contentShape(Capsule())
            .gesture(PadHold.drag(onHeld))
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}

@available(iOS 18.0, *)
struct PadOvalButton: View {
    let title: String
    let isHeld: Bool
    var minWidth: CGFloat = 64
    var minHeight: CGFloat = 44
    var rotation: Angle = .zero
    var fill: Color
    var ink: Color
    var interactive: Bool = true
    let onHeld: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .background {
                Capsule()
                    .fill(fill)
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(isHeld ? 0.5 : 0.2), lineWidth: 1)
            }
            .rotationEffect(rotation)
            .scaleEffect(isHeld ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isHeld)
            .contentShape(Capsule())
            .padHoldIf(interactive, onHeld)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(!interactive)
    }
}

@available(iOS 18.0, *)
struct PadChassis<Content: View>: View {
    var fill: Color
    var stroke: Color
    var cornerRadius: CGFloat = 26
    var content: Content

    init(
        fill: Color,
        stroke: Color,
        cornerRadius: CGFloat = 26,
        @ViewBuilder content: () -> Content
    ) {
        self.fill = fill
        self.stroke = stroke
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1.2)
                    }
            }
    }
}

// MARK: - D-pad

@available(iOS 18.0, *)
struct CrossDPad: View {
    var size: CGFloat = 128
    var armThickness: CGFloat = 46
    var isUp: Bool
    var isDown: Bool
    var isLeft: Bool
    var isRight: Bool
    var fill: Color
    var heldFill: Color
    var ink: Color = Color.white.opacity(0.78)
    var onChange: @MainActor @Sendable (_ up: Bool, _ down: Bool, _ left: Bool, _ right: Bool) -> Void

    var body: some View {
        let pit = armThickness * 0.38
        ZStack {
            PlusShape(armThickness: armThickness)
                .fill(fill)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)

            PlusShape(armThickness: armThickness)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)

            armHighlight(active: isUp, offset: CGSize(width: 0, height: -(size - armThickness) / 4))
            armHighlight(active: isDown, offset: CGSize(width: 0, height: (size - armThickness) / 4))
            armHighlight(active: isLeft, offset: CGSize(width: -(size - armThickness) / 4, height: 0))
            armHighlight(active: isRight, offset: CGSize(width: (size - armThickness) / 4, height: 0))

            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(isUp ? 1 : 0.55))
                .offset(y: -(size * 0.32))
                .accessibilityHidden(true)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(isDown ? 1 : 0.55))
                .offset(y: size * 0.32)
                .accessibilityHidden(true)
            Image(systemName: "arrowtriangle.left.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(isLeft ? 1 : 0.55))
                .offset(x: -(size * 0.32))
                .accessibilityHidden(true)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(ink.opacity(isRight ? 1 : 0.55))
                .offset(x: size * 0.32)
                .accessibilityHidden(true)

            Circle()
                .fill(Color.black.opacity(0.28))
                .frame(width: pit, height: pit)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        }
        .frame(width: size, height: size)
        .contentShape(PlusShape(armThickness: armThickness + 8))
        .gesture(dpadGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("D-pad")
        .accessibilityValue(heldDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Up") { pulse(.up) }
        .accessibilityAction(named: "Down") { pulse(.down) }
        .accessibilityAction(named: "Left") { pulse(.left) }
        .accessibilityAction(named: "Right") { pulse(.right) }
    }

    private var heldDescription: String {
        var parts: [String] = []
        if isUp { parts.append("Up") }
        if isDown { parts.append("Down") }
        if isLeft { parts.append("Left") }
        if isRight { parts.append("Right") }
        return parts.isEmpty ? "Released" : parts.joined(separator: ", ")
    }

    private func armHighlight(active: Bool, offset: CGSize) -> some View {
        Capsule()
            .fill(heldFill.opacity(active ? 0.95 : 0))
            .frame(width: armThickness * 0.72, height: armThickness * 0.72)
            .offset(offset)
            .animation(.easeOut(duration: 0.08), value: active)
    }

    private var dpadGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = Double(value.location.x - size / 2)
                let dy = Double(value.location.y - size / 2)
                let bits = PadHitTesting.dpad(dx: dx, dy: dy, deadzone: 12)
                onChange(bits.up, bits.down, bits.left, bits.right)
            }
            .onEnded { _ in
                onChange(false, false, false, false)
            }
    }

    private enum PulseDir { case up, down, left, right }

    private func pulse(_ dir: PulseDir) {
        switch dir {
        case .up: onChange(true, false, false, false)
        case .down: onChange(false, true, false, false)
        case .left: onChange(false, false, true, false)
        case .right: onChange(false, false, false, true)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            onChange(false, false, false, false)
        }
    }
}

@available(iOS 18.0, *)
extension View {
    @ViewBuilder
    func padHoldIf(_ enabled: Bool, _ onHeld: @escaping @MainActor @Sendable (Bool) -> Void) -> some View {
        if enabled {
            self.gesture(PadHold.drag(onHeld))
        } else {
            self
        }
    }
}

// MARK: - Analog well

/// Circular nub in an octagonal gate. Interactive wells report Int8 XY via `PadHitTesting.analog`.
@available(iOS 18.0, *)
struct AnalogStickWell: View {
    var wellSize: CGFloat = 96
    /// Stick space −1…1 (Y up).
    var x: CGFloat
    var y: CGFloat
    var wellFill: Color = PadPalette.N64.stickWell
    var nubFill: Color = PadPalette.N64.stickNub
    var interactive: Bool = true
    var accessibilityName: String = "Analog stick"
    var onChange: @MainActor @Sendable (Int8, Int8) -> Void

    var body: some View {
        let nub = wellSize * 0.42
        let travel = (wellSize - nub) / 2 - 3
        ZStack {
            RegularOctagon()
                .fill(wellFill)
                .overlay {
                    RegularOctagon()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.2)
                }
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)
                .frame(width: wellSize * 0.78, height: wellSize * 0.78)
            Circle()
                .fill(nubFill)
                .frame(width: nub, height: nub)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .offset(x: x * travel, y: -y * travel)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
        .frame(width: wellSize, height: wellSize)
        .contentShape(Circle())
        .gesture(stickGesture)
        .allowsHitTesting(interactive)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(interactive ? "X \(Int(x * 80)), Y \(Int(y * 80))" : "Not wired")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!interactive)
    }

    private var stickGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = Double(value.location.x - wellSize / 2)
                let dy = Double(value.location.y - wellSize / 2)
                let sample = PadHitTesting.analog(
                    dx: dx,
                    dy: dy,
                    radius: Double(wellSize / 2)
                )
                onChange(sample.x, sample.y)
            }
            .onEnded { _ in
                onChange(0, 0)
            }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

// Display-only pad pieces. None of them has a gesture: each reports its frame with
// `padRegion`, and `PadTouchSurface` turns touches into input. Held state comes from
// the `PadInputModel` in the environment, so on-screen, controller and keyboard
// presses all light the same buttons.

private let pressAnimation = Animation.easeOut(duration: 0.06)

/// How far every control shrinks while pressed (buttons, shoulders, SELECT / START, the D-pad's
/// arms and its arrows, the stick's knob, the in-game buttons): one ratio for all of them.
let padPressScale: CGFloat = 0.94

/// Press feedback for SwiftUI buttons (the in-game fast-forward / pause / sound row).
struct PadPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? padPressScale : 1)
            .animation(pressAnimation, value: configuration.isPressed)
    }
}

extension EnvironmentValues {
    /// Controls drawn over the game (landscape): fills are see-through so the picture shows.
    @Entry var padGlass = false
    /// A shoulder's outer corner, concentric with the backing's corner; nil: a half-height round.
    @Entry var padOuterCornerRadius: CGFloat? = nil
}

extension Color {
    /// This fill, see-through when the pad is drawn over the game.
    func padFill(glass: Bool) -> Color { glass ? opacity(0.65) : self }

    /// This fill as a Liquid Glass tint (portrait, on the pad's backing).
    func padTint(glass: Bool, held: Bool = false) -> Color {
        opacity(held ? 1 : (glass ? 0.45 : 0.8))
    }

    /// A label over untinted glass (landscape): the button's colour moves to its label so
    /// A / B / C stay recognisable, and dark ink turns light so it reads over the game.
    static func padLabel(fill: Color, ink: Color, glass: Bool) -> Color {
        guard glass, padLiquidGlass else { return ink }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(fill).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation > 0.35 && brightness > 0.35 { return fill }
        var inkBrightness: CGFloat = 0
        UIColor(ink).getHue(nil, saturation: nil, brightness: &inkBrightness, alpha: nil)
        return inkBrightness < 0.5 ? Color.white.opacity(0.92) : ink
    }
}

/// Liquid Glass controls: iOS 26 and later, unless Settings → Flat Controls is on. Otherwise
/// every control draws its flat fill (`padSurface`'s fallback). Read when a control draws, so
/// the setting applies to the next game without anything else to keep in sync.
var padLiquidGlass: Bool {
    guard #available(iOS 26.0, *) else { return false }
    return !UserDefaults.standard.bool(forKey: PlaySettingsKey.flatControls)
}

extension View {
    /// A control's surface on Liquid Glass. Over the game (`clear`, landscape) it's the
    /// clearest glass with no tint, so the picture shows; on the pad's backing it's tinted
    /// with the button's colour. Flat controls (or before iOS 26): `fallback` drawn behind it.
    @ViewBuilder
    func padSurface<S: Shape, Fallback: View>(
        _ shape: S,
        tint: Color,
        clear: Bool = false,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(iOS 26.0, *), padLiquidGlass {
            glassEffect(clear ? .clear : .regular.tint(tint), in: shape)
        } else {
            background { ZStack { fallback() } }
        }
    }
}

/// Flat-sided buttons (shoulders, SELECT / START, the in-game row) share the backing's
/// corner language: a shoulder's outer corner follows the controller's corner (a full
/// half-height round, which is where the concentric radius lands on every iPhone), and
/// the other corners use this fraction of the button's height.
let padCornerFraction: CGFloat = 0.3

@available(iOS 18.0, *)
struct PadFaceButton: View {
    @Environment(PadInputModel.self) private var input
    @Environment(\.padGlass) private var glass
    let title: String
    let bits: UInt32
    var diameter: CGFloat = 56
    var fill: Color
    var ink: Color
    var stroke: Color = Color.white.opacity(0.22)
    var accessibilityName: String? = nil

    /// The PSP's △ drawn as a true equilateral triangle (the font's glyph is tall and narrow);
    /// every other label is text.
    @ViewBuilder private var label: some View {
        if title == "△" {
            let side = diameter * 0.40
            EquilateralTriangle()
                .stroke(style: StrokeStyle(lineWidth: max(2, diameter * 0.075), lineJoin: .round))
                .frame(width: side, height: side * 0.866)
                // Centre the triangle's centroid, not its box, on the button.
                .offset(y: -side * 0.866 / 6)
        } else {
            Text(title).font(labelFont)
        }
    }

    /// Letters in the pixel font; symbols (PSP △○✕□, N64 C arrows) larger and heavy so they read.
    private var labelFont: Font {
        if title.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            return RetroPlayFont.sized(max(11, diameter * 0.34), relativeTo: .body)
        }
        return .system(size: max(12, diameter * 0.44), weight: .heavy)
    }

    var body: some View {
        let held = input.isHeld(bits)
        label
            .foregroundStyle(Color.padLabel(fill: fill, ink: ink, glass: glass))
            .frame(width: diameter, height: diameter)
            .padSurface(Circle(), tint: fill.padTint(glass: glass, held: held), clear: glass) {
                Circle()
                    .fill(fill.padFill(glass: glass))
                    .brightness(held ? 0.12 : 0)
                    .shadow(color: .black.opacity(held ? 0.08 : 0.3), radius: held ? 1 : 3, y: held ? 0 : 2)
            }
            .overlay {
                // Glass has its own rim and shows a press by shrinking, so no outline there.
                if !padLiquidGlass {
                    Circle().strokeBorder(stroke.opacity(held ? 1 : 0.7), lineWidth: held ? 2 : 1)
                }
            }
            .scaleEffect(held ? padPressScale : 1)
            .animation(pressAnimation, value: held)
            .padRegion("button.\(bits)", .button(bits), shape: .circle)
            .accessibilityElement()
            .accessibilityLabel(accessibilityName ?? title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { input.pulse(bits) }
    }
}

@available(iOS 18.0, *)
struct PadShoulderButton: View {
    @Environment(PadInputModel.self) private var input
    @Environment(\.padGlass) private var glass
    let title: String
    let bits: UInt32
    var width: CGFloat = 84
    var height: CGFloat = 40
    var fill: Color
    var ink: Color
    /// The side whose top corner meets the controller's corner.
    var outer: HorizontalEdge? = nil

    @Environment(\.padOuterCornerRadius) private var outerRadius

    private var shape: UnevenRoundedRectangle {
        let corner = height * padCornerFraction
        // The outer corner can take most of the button's height; the corner under it gives way.
        let outerCorner = min(outerRadius ?? height / 2, height - 4, width / 2)
        let underOuter = min(corner, max(4, height - outerCorner))
        return UnevenRoundedRectangle(
            topLeadingRadius: outer == .leading ? outerCorner : corner,
            bottomLeadingRadius: outer == .leading ? underOuter : corner,
            bottomTrailingRadius: outer == .trailing ? underOuter : corner,
            topTrailingRadius: outer == .trailing ? outerCorner : corner,
            style: .continuous
        )
    }

    var body: some View {
        let held = input.isHeld(bits)
        Text(title)
            .font(RetroPlayFont.sized(max(11, height * 0.34), relativeTo: .subheadline))
            .foregroundStyle(Color.padLabel(fill: fill, ink: ink, glass: glass))
            .frame(width: width, height: height)
            .padSurface(shape, tint: fill.padTint(glass: glass, held: held), clear: glass) {
                shape
                    .fill(fill.padFill(glass: glass))
                    .brightness(held ? 0.12 : 0)
            }
            .overlay {
                if !padLiquidGlass {
                    shape.strokeBorder(Color.white.opacity(held ? 0.5 : 0.18), lineWidth: held ? 2 : 1)
                }
            }
            .scaleEffect(held ? padPressScale : 1)
            .animation(pressAnimation, value: held)
            .padRegion("shoulder.\(bits)", .button(bits))
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { input.pulse(bits) }
    }
}

/// Small Start / Select capsule.
@available(iOS 18.0, *)
struct PadPillButton: View {
    @Environment(PadInputModel.self) private var input
    @Environment(\.padGlass) private var glass
    let title: String
    let bits: UInt32
    var scale: CGFloat = 1
    var fill: Color
    var ink: Color

    /// SELECT / START are drawn at half the area (each side × √½); the touch area keeps its
    /// full height, so they're as easy to hit.
    static let sizeFactor: CGFloat = 0.71
    private var drawn: CGFloat { scale * Self.sizeFactor }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26 * drawn * padCornerFraction, style: .continuous)
    }

    var body: some View {
        let held = input.isHeld(bits)
        // Every pill is as wide as the longest label ("SELECT"), so START, SELECT and the 7800's
        // switches match; the hidden text sets that width and grows with Dynamic Type.
        ZStack {
            Text("SELECT").hidden()
            Text(title)
                // Over the game the capsule is mostly see-through, so a dark label would vanish.
                .foregroundStyle(glass ? Color.white.opacity(0.9) : ink)
        }
            .font(RetroPlayFont.sized(max(8, 10 * drawn), relativeTo: .caption2))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12 * drawn)
            .padding(.vertical, 4 * drawn)
            .frame(minWidth: 74 * drawn, minHeight: 26 * drawn)
            .padSurface(shape, tint: fill.padTint(glass: glass, held: held), clear: glass) {
                shape.fill(glass ? fill.opacity(0.3) : fill).brightness(held ? 0.15 : 0)
            }
            .overlay {
                if !padLiquidGlass {
                    shape.strokeBorder(Color.white.opacity(held ? 0.5 : 0.2), lineWidth: 1)
                }
            }
            .scaleEffect(held ? padPressScale : 1)
            .animation(pressAnimation, value: held)
            // Pills are small; give them a finger-sized hit area (the full-size pill's height).
            .padding(.vertical, 8 * scale + 13 * (scale - drawn))
            .padding(.horizontal, 6 * scale)
            .contentShape(Rectangle())
            .padRegion("pill.\(bits)", .button(bits))
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { input.pulse(bits) }
    }
}

@available(iOS 18.0, *)
struct PadDPad: View {
    @Environment(PadInputModel.self) private var input
    @Environment(\.padGlass) private var glass
    var size: CGFloat = 150
    let up: UInt32
    let down: UInt32
    let left: UInt32
    let right: UInt32
    var fill: Color
    var heldFill: Color
    var ink: Color = Color.white.opacity(0.78)

    var body: some View {
        let armWidth = size * 0.36
        let travel = (size - armWidth) / 2
        let shape = PressablePlusShape(
            armThickness: armWidth,
            up: input.isHeld(up) ? 1 : 0, down: input.isHeld(down) ? 1 : 0,
            left: input.isHeld(left) ? 1 : 0, right: input.isHeld(right) ? 1 : 0
        )
        ZStack {
            Color.clear
                .padSurface(shape, tint: fill.padTint(glass: glass), clear: glass) {
                    shape
                        .fill(fill.padFill(glass: glass))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    shape
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            arrowView(bits: up, arrow: "arrowtriangle.up.fill", direction: CGSize(width: 0, height: -1), travel: travel, arm: armWidth)
            arrowView(bits: down, arrow: "arrowtriangle.down.fill", direction: CGSize(width: 0, height: 1), travel: travel, arm: armWidth)
            arrowView(bits: left, arrow: "arrowtriangle.left.fill", direction: CGSize(width: -1, height: 0), travel: travel, arm: armWidth)
            arrowView(bits: right, arrow: "arrowtriangle.right.fill", direction: CGSize(width: 1, height: 0), travel: travel, arm: armWidth)
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: armWidth * 0.42, height: armWidth * 0.42)
        }
        .animation(pressAnimation, value: shape.animatableData)
        .frame(width: size, height: size)
        .padRegion("dpad.\(up)", .dpad(up: up, down: down, left: left, right: right))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("D-pad")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Up") { input.pulse(up) }
        .accessibilityAction(named: "Down") { input.pulse(down) }
        .accessibilityAction(named: "Left") { input.pulse(left) }
        .accessibilityAction(named: "Right") { input.pulse(right) }
    }

    /// The arrow rides on its arm: when the arm pulls in, the arrow comes with it and shrinks.
    private func arrowView(bits: UInt32, arrow: String, direction: CGSize, travel: CGFloat, arm: CGFloat) -> some View {
        let held = input.isHeld(bits)
        let distance = travel * (held ? 1 - PressablePlusShape.pressedRetract : 1)
        return Image(systemName: arrow)
            .font(.system(size: max(8, arm * 0.26), weight: .bold))
            .foregroundStyle(ink.opacity(held ? 1 : 0.55))
            .scaleEffect(held ? padPressScale : 1)
            .offset(x: direction.width * distance, y: direction.height * distance)
            .animation(pressAnimation, value: held)
    }
}

/// The D-pad as one joined cross whose arms pull in when pressed (0 = up, 1 = pressed): the
/// pressed arm gets shorter and a little narrower, still attached to the centre, so the glass
/// shows the press the way the round buttons shrink. Diagonals pull in two arms.
@available(iOS 18.0, *)
struct PressablePlusShape: Shape {
    /// A pressed arm shrinks by the same ratio as every other control, in length and width.
    static let pressedRetract: CGFloat = 1 - padPressScale
    static let pressedNarrow: CGFloat = 1 - padPressScale

    var armThickness: CGFloat
    var up: CGFloat, down: CGFloat, left: CGFloat, right: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(up, down), AnimatablePair(left, right)) }
        set { up = newValue.first.first; down = newValue.first.second; left = newValue.second.first; right = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(armThickness, rect.width, rect.height)
        let cx = rect.midX, cy = rect.midY
        let reachX = rect.width / 2, reachY = rect.height / 2
        let radius = t * 0.22
        var path = Path()
        func arm(_ press: CGFloat, vertical: Bool, sign: CGFloat) {
            let reach = (vertical ? reachY : reachX) * (1 - Self.pressedRetract * press)
            let width = t * (1 - Self.pressedNarrow * press)
            // From the far side of the centre square out to the arm's tip, so arms always join.
            let start = -t / 2, end = reach
            let lo = min(sign * start, sign * end), hi = max(sign * start, sign * end)
            let r = vertical
                ? CGRect(x: cx - width / 2, y: cy + lo, width: width, height: hi - lo)
                : CGRect(x: cx + lo, y: cy - width / 2, width: hi - lo, height: width)
            path.addRoundedRect(in: r, cornerSize: CGSize(width: radius, height: radius))
        }
        arm(up, vertical: true, sign: -1)
        arm(down, vertical: true, sign: 1)
        arm(left, vertical: false, sign: -1)
        arm(right, vertical: false, sign: 1)
        return path
    }
}

/// Analog stick: octagonal gate + nub that follows touch or a physical stick.
@available(iOS 18.0, *)
struct PadStick: View {
    @Environment(PadInputModel.self) private var input
    @Environment(\.padGlass) private var glass
    var size: CGFloat = 110
    var gateFill: Color
    var nubFill: Color
    var octagonal = true
    var accessibilityName = "Analog stick"

    /// How far the knob moves from the centre at full tilt, as a fraction of the stick's size.
    static let travelFraction: CGFloat = 0.30
    /// How far the thumb moves for full tilt: three quarters of the knob's travel. A thumb's
    /// touch point sits a little inside where it feels it's pressing, and the landscape stick
    /// is close to the screen's bottom edge, so at a 1:1 distance a full push down often read
    /// as 70–80% (a walk instead of a run). Past this it holds full tilt.
    static let touchTravelFraction: CGFloat = travelFraction * 0.75

    var body: some View {
        let nub = size * 0.46
        let travel = size * Self.travelFraction
        let stick = input.stick
        ZStack {
            if octagonal {
                Color.clear.padSurface(RegularOctagon(), tint: gateFill.padTint(glass: glass), clear: glass) {
                    RegularOctagon().fill(gateFill.padFill(glass: glass))
                    RegularOctagon().stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                }
            } else {
                Color.clear.padSurface(Circle(), tint: gateFill.padTint(glass: glass), clear: glass) {
                    Circle().fill(gateFill.padFill(glass: glass))
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1.2)
                }
            }
            Color.clear
                .frame(width: nub, height: nub)
                .padSurface(Circle(), tint: nubFill.padTint(glass: false), clear: glass) {
                    Circle().fill(nubFill)
                    Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                // Pressed down while a thumb (or stick) moves it, like the buttons.
                .scaleEffect(stick.x != 0 || stick.y != 0 ? padPressScale : 1)
                .animation(pressAnimation, value: stick.x != 0 || stick.y != 0)
                .offset(x: CGFloat(stick.x) * travel, y: CGFloat(-stick.y) * travel)
        }
        .frame(width: size, height: size)
        .padRegion("stick", .stick, shape: .circle)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
    }
}

/// Four buttons in a diamond (PSP △○✕□, DS XAYB, N64 C buttons).
@available(iOS 18.0, *)
struct PadDiamond: View {
    struct Item {
        var title: String
        var bits: UInt32
        var fill: Color
        var ink: Color
        var name: String? = nil
    }

    let top: Item
    let right: Item
    let bottom: Item
    let left: Item
    var diameter: CGFloat = 52

    var body: some View {
        let reach = diameter * 0.9
        ZStack {
            button(top).offset(y: -reach)
            button(right).offset(x: reach)
            button(bottom).offset(y: reach)
            button(left).offset(x: -reach)
        }
        .frame(width: reach * 2 + diameter, height: reach * 2 + diameter)
    }

    private func button(_ item: Item) -> some View {
        PadFaceButton(
            title: item.title,
            bits: item.bits,
            diameter: diameter,
            fill: item.fill,
            ink: item.ink,
            accessibilityName: item.name
        )
    }
}

/// Three equal sides, point up, filling its frame's width.
struct EquilateralTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.width * 0.866
        let top = rect.midY - h / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top + h))
        path.addLine(to: CGPoint(x: rect.minX, y: top + h))
        path.closeSubpath()
        return path
    }
}

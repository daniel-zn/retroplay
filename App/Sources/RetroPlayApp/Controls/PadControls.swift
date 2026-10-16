// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

// Display-only pad pieces. None of them has a gesture: each reports its frame with
// `padRegion`, and `PadTouchSurface` turns touches into input. Held state comes from
// the `PadInputModel` in the environment, so on-screen, controller and keyboard
// presses all light the same buttons.

private let pressAnimation = Animation.easeOut(duration: 0.06)

extension EnvironmentValues {
    /// Controls drawn over the game (landscape): fills are see-through so the picture shows.
    @Entry var padGlass = false
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

/// Liquid Glass controls (iOS 26 and later); earlier systems draw the flat fills.
let padLiquidGlass: Bool = {
    if #available(iOS 26.0, *) { return true }
    return false
}()

extension View {
    /// A control's surface on Liquid Glass. Over the game (`clear`, landscape) it's the
    /// clearest glass with no tint, so the picture shows; on the pad's backing it's tinted
    /// with the button's colour. Before iOS 26, `fallback` is drawn behind it as before.
    @ViewBuilder
    func padSurface<S: Shape, Fallback: View>(
        _ shape: S,
        tint: Color,
        clear: Bool = false,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(iOS 26.0, *) {
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

    var body: some View {
        let held = input.isHeld(bits)
        Text(title)
            .font(RetroPlayFont.sized(max(11, diameter * 0.34), relativeTo: .body))
            .foregroundStyle(Color.padLabel(fill: fill, ink: ink, glass: glass))
            .frame(width: diameter, height: diameter)
            .padSurface(Circle(), tint: fill.padTint(glass: glass, held: held), clear: glass) {
                Circle()
                    .fill(fill.padFill(glass: glass))
                    .brightness(held ? 0.12 : 0)
                    .shadow(color: .black.opacity(held ? 0.08 : 0.3), radius: held ? 1 : 3, y: held ? 0 : 2)
            }
            .overlay {
                // Glass has its own rim; the outline then only marks a press.
                if held || !padLiquidGlass {
                    Circle().strokeBorder(stroke.opacity(held ? 1 : 0.7), lineWidth: held ? 2 : 1)
                }
            }
            .scaleEffect(held ? 0.92 : 1)
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

    private var shape: UnevenRoundedRectangle {
        let corner = height * padCornerFraction
        return UnevenRoundedRectangle(
            topLeadingRadius: outer == .leading ? height / 2 : corner,
            bottomLeadingRadius: corner,
            bottomTrailingRadius: corner,
            topTrailingRadius: outer == .trailing ? height / 2 : corner,
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
                if held || !padLiquidGlass {
                    shape.strokeBorder(Color.white.opacity(held ? 0.5 : 0.18), lineWidth: held ? 2 : 1)
                }
            }
            .scaleEffect(held ? 0.95 : 1)
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

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 26 * scale * padCornerFraction, style: .continuous)
    }

    var body: some View {
        let held = input.isHeld(bits)
        Text(title)
            .font(RetroPlayFont.sized(max(8, 10 * scale), relativeTo: .caption2))
            // Over the game the capsule is mostly see-through, so a dark label would vanish.
            .foregroundStyle(glass ? Color.white.opacity(0.9) : ink)
            .lineLimit(1)
            // The label grows with Dynamic Type, so the capsule sizes to it instead of a fixed width.
            .fixedSize()
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 4 * scale)
            .frame(minWidth: 74 * scale, minHeight: 26 * scale)
            .padSurface(shape, tint: fill.padTint(glass: glass, held: held), clear: glass) {
                shape.fill(glass ? fill.opacity(0.3) : fill).brightness(held ? 0.15 : 0)
            }
            .overlay {
                if held || !padLiquidGlass {
                    shape.strokeBorder(Color.white.opacity(held ? 0.5 : 0.2), lineWidth: 1)
                }
            }
            .scaleEffect(held ? 0.94 : 1)
            .animation(pressAnimation, value: held)
            // Pills are small; give them a finger-sized hit area.
            .padding(.vertical, 8 * scale)
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
        ZStack {
            Color.clear
                .padSurface(PlusShape(armThickness: armWidth), tint: fill.padTint(glass: glass), clear: glass) {
                    PlusShape(armThickness: armWidth)
                        .fill(fill.padFill(glass: glass))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    PlusShape(armThickness: armWidth)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            armView(bits: up, arrow: "arrowtriangle.up.fill", offset: CGSize(width: 0, height: -travel), arm: armWidth)
            armView(bits: down, arrow: "arrowtriangle.down.fill", offset: CGSize(width: 0, height: travel), arm: armWidth)
            armView(bits: left, arrow: "arrowtriangle.left.fill", offset: CGSize(width: -travel, height: 0), arm: armWidth)
            armView(bits: right, arrow: "arrowtriangle.right.fill", offset: CGSize(width: travel, height: 0), arm: armWidth)
            Circle()
                .fill(Color.black.opacity(0.25))
                .frame(width: armWidth * 0.42, height: armWidth * 0.42)
        }
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

    private func armView(bits: UInt32, arrow: String, offset: CGSize, arm: CGFloat) -> some View {
        let held = input.isHeld(bits)
        return ZStack {
            RoundedRectangle(cornerRadius: arm * 0.2, style: .continuous)
                .fill(heldFill.opacity(held ? 1 : 0))
                .frame(width: arm * 0.86, height: arm * 0.86)
            Image(systemName: arrow)
                .font(.system(size: max(8, arm * 0.24), weight: .bold))
                .foregroundStyle(ink.opacity(held ? 1 : 0.5))
        }
        .offset(offset)
        .animation(pressAnimation, value: held)
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

    var body: some View {
        let nub = size * 0.46
        let travel = size * 0.30
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

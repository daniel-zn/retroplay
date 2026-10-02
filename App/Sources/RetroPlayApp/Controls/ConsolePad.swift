// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// Per-system pad pieces. Portrait stacks them under the screen; landscape puts
/// them in the thumb zones either side of it. Hardware layouts follow docs/CONTROLS-*.md.
@available(iOS 18.0, *)
@MainActor
struct ConsolePad {
    let system: SystemID
    /// 1 ≈ a 390 pt-wide iPhone in portrait.
    let scale: CGFloat
    /// Portrait has height to spare under the screen: taller shoulders and larger face
    /// buttons. Landscape keeps the narrower sizes so its side columns stay off the game.
    var portrait = false

    // MARK: Shoulders

    @ViewBuilder var leftShoulders: some View {
        switch system {
        case .gba:
            shoulder("L", GBAInput.l.bits, PadPalette.GBA.shoulder, PadPalette.GBA.ink)
        case .psp:
            shoulder("L", PSPInput.l.rawValue, PadPalette.PSP.nub, PadPalette.PSP.ink)
        case .nds:
            shoulder("L", NDSInput.l.rawValue, PadPalette.NDS.shoulder, PadPalette.NDS.ink)
        case .n64:
            // Z is the trigger N64 games lean on (Z-targeting, crouch, shoot); L is rarely
            // used, so Z gets the big button and L sits beside it.
            HStack(spacing: 8 * scale) {
                shoulder("Z", N64Input.z.rawValue, PadPalette.N64.z, PadPalette.N64.inkLight, width: portrait ? 96 : 84)
                shoulder("L", N64Input.l.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight, width: portrait ? 56 : 48)
            }
        }
    }

    @ViewBuilder var rightShoulders: some View {
        switch system {
        case .gba:
            shoulder("R", GBAInput.r.bits, PadPalette.GBA.shoulder, PadPalette.GBA.ink)
        case .psp:
            shoulder("R", PSPInput.r.rawValue, PadPalette.PSP.nub, PadPalette.PSP.ink)
        case .nds:
            shoulder("R", NDSInput.r.rawValue, PadPalette.NDS.shoulder, PadPalette.NDS.ink)
        case .n64:
            shoulder("R", N64Input.r.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight)
        }
    }

    // MARK: Thumb clusters

    @ViewBuilder var leftMain: some View {
        switch system {
        case .gba:
            PadDPad(
                size: (portrait ? 156 : 150) * scale,
                up: GBAInput.up.bits, down: GBAInput.down.bits,
                left: GBAInput.left.bits, right: GBAInput.right.bits,
                fill: PadPalette.GBA.dpad, heldFill: PadPalette.GBA.dpadHeld
            )
        case .psp:
            // Real PSP: D-pad above, analog nub below.
            VStack(spacing: (portrait ? 18 : 10) * scale) {
                PadDPad(
                    size: (portrait ? 144 : 136) * scale,
                    up: PSPInput.up.rawValue, down: PSPInput.down.rawValue,
                    left: PSPInput.left.rawValue, right: PSPInput.right.rawValue,
                    fill: PadPalette.PSP.dpad, heldFill: PadPalette.PSP.nub
                )
                PadStick(
                    size: (portrait ? 108 : 96) * scale,
                    gateFill: Color(red: 0.16, green: 0.16, blue: 0.17),
                    nubFill: PadPalette.PSP.nub,
                    octagonal: false,
                    accessibilityName: "Analog nub"
                )
            }
        case .nds:
            PadDPad(
                size: (portrait ? 152 : 146) * scale,
                up: NDSInput.up.rawValue, down: NDSInput.down.rawValue,
                left: NDSInput.left.rawValue, right: NDSInput.right.rawValue,
                fill: PadPalette.NDS.dpad, heldFill: PadPalette.NDS.shoulder
            )
        case .n64:
            // The Control Stick is what N64 games are played with, so it takes the low spot
            // where the thumb rests; the rarely used D-pad sits above it.
            VStack(spacing: (portrait ? 16 : 10) * scale) {
                PadDPad(
                    size: (portrait ? 108 : 100) * scale,
                    up: N64Input.dpadUp.rawValue, down: N64Input.dpadDown.rawValue,
                    left: N64Input.dpadLeft.rawValue, right: N64Input.dpadRight.rawValue,
                    fill: PadPalette.N64.dpad, heldFill: PadPalette.N64.chassisDark
                )
                PadStick(
                    size: (portrait ? 136 : 128) * scale,
                    gateFill: PadPalette.N64.stickWell,
                    nubFill: PadPalette.N64.stickNub,
                    accessibilityName: "Control Stick"
                )
            }
        }
    }

    @ViewBuilder var rightMain: some View {
        switch system {
        case .gba:
            twoButtons(
                primary: ("A", GBAInput.a.bits, PadPalette.GBA.faceA),
                secondary: ("B", GBAInput.b.bits, PadPalette.GBA.face),
                diameter: (portrait ? 78 : 74) * scale,
                ink: PadPalette.GBA.ink
            )
        case .psp:
            PadDiamond(
                top: .init(title: "△", bits: PSPInput.triangle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.triangle, name: "Triangle"),
                right: .init(title: "○", bits: PSPInput.circle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.circle, name: "Circle"),
                bottom: .init(title: "✕", bits: PSPInput.cross.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.cross, name: "Cross"),
                left: .init(title: "□", bits: PSPInput.square.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.square, name: "Square"),
                diameter: (portrait ? 60 : 54) * scale
            )
        case .nds:
            PadDiamond(
                top: .init(title: "X", bits: NDSInput.x.rawValue, fill: PadPalette.NDS.x, ink: PadPalette.NDS.ink),
                right: .init(title: "A", bits: NDSInput.a.rawValue, fill: PadPalette.NDS.a, ink: PadPalette.NDS.ink),
                bottom: .init(title: "B", bits: NDSInput.b.rawValue, fill: PadPalette.NDS.b, ink: PadPalette.NDS.inkDark),
                left: .init(title: "Y", bits: NDSInput.y.rawValue, fill: PadPalette.NDS.y, ink: PadPalette.NDS.ink),
                diameter: (portrait ? 60 : 54) * scale
            )
        case .n64:
            VStack(spacing: (portrait ? 14 : 6) * scale) {
                PadDiamond(
                    top: .init(title: "▲", bits: N64Input.cUp.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Up"),
                    right: .init(title: "▶", bits: N64Input.cRight.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Right"),
                    bottom: .init(title: "▼", bits: N64Input.cDown.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Down"),
                    left: .init(title: "◀", bits: N64Input.cLeft.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Left"),
                    diameter: (portrait ? 44 : 40) * scale
                )
                // Hardware: green B up-left of the larger blue A.
                let k: CGFloat = portrait ? 1.08 : 1
                ZStack {
                    PadFaceButton(title: "B", bits: N64Input.b.rawValue, diameter: 56 * k * scale, fill: PadPalette.N64.b, ink: PadPalette.N64.inkLight)
                        .offset(x: -30 * k * scale, y: -18 * k * scale)
                    PadFaceButton(title: "A", bits: N64Input.a.rawValue, diameter: 66 * k * scale, fill: PadPalette.N64.a, ink: PadPalette.N64.inkLight)
                        .offset(x: 30 * k * scale, y: 18 * k * scale)
                }
                .frame(width: 136 * k * scale, height: 108 * k * scale)
            }
        }
    }

    // MARK: Center

    @ViewBuilder var center: some View {
        switch system {
        case .gba:
            pills(select: GBAInput.select.bits, start: GBAInput.start.bits, fill: PadPalette.GBA.startSelect, ink: PadPalette.GBA.ink)
        case .psp:
            pills(select: PSPInput.select.rawValue, start: PSPInput.start.rawValue, fill: PadPalette.PSP.silver, ink: PadPalette.PSP.chassis)
        case .nds:
            pills(select: NDSInput.select.rawValue, start: NDSInput.start.rawValue, fill: PadPalette.NDS.shoulder, ink: PadPalette.NDS.ink)
        case .n64:
            PadPillButton(title: "START", bits: N64Input.start.rawValue, scale: pillScale, fill: PadPalette.N64.start, ink: PadPalette.N64.inkLight)
        }
    }

    /// SELECT / START are easy to miss at landscape size; portrait has room for bigger ones.
    private var pillScale: CGFloat { portrait ? scale * 1.25 : scale }

    // MARK: Landscape columns

    /// Width each landscape side column needs: the wider of its two thumb clusters
    /// (D-pad / stick on the left, face buttons on the right), so a fitted screen
    /// can sit between the columns without anything overlapping it.
    var landscapeColumnWidth: CGFloat {
        switch system {
        case .gba: return 150 * scale
        case .psp, .nds: return 151 * scale
        case .n64: return 140 * scale
        }
    }

    /// Height of the taller landscape side column at scale 1 (shoulders, pause row,
    /// thumb cluster, SELECT / START and the gaps between them), with a little margin.
    private static func landscapeColumnHeight(_ system: SystemID) -> CGFloat {
        switch system {
        case .gba: return 300
        case .nds: return 315
        case .psp: return 355
        case .n64: return 385
        }
    }

    /// Landscape size: the phone-height default, grown while the taller column still fits
    /// and a fitted screen keeps its full height between the columns. Narrow pictures
    /// (DS) leave wide columns, so their controls gain the most.
    static func landscapeScale(for system: SystemID, in size: CGSize) -> CGFloat {
        let base = min(max(size.height / 390, 0.66), 1.15)
        let unitColumn = ConsolePad(system: system, scale: 1).landscapeColumnWidth
        let heightFit = (size.height - 12) / landscapeColumnHeight(system)
        let pictureWidth = size.height * CGFloat(system.screenAspect)
        let widthFit = (size.width - 24 - pictureWidth) / 2 / unitColumn
        return max(base, min(heightFit, widthFit, 1.45))
    }

    /// SELECT alone, for the bottom of the left landscape column (N64 has none).
    @ViewBuilder var selectButton: some View {
        switch system {
        case .gba:
            PadPillButton(title: "SELECT", bits: GBAInput.select.bits, scale: scale, fill: PadPalette.GBA.startSelect, ink: PadPalette.GBA.ink)
        case .psp:
            PadPillButton(title: "SELECT", bits: PSPInput.select.rawValue, scale: scale, fill: PadPalette.PSP.silver, ink: PadPalette.PSP.chassis)
        case .nds:
            PadPillButton(title: "SELECT", bits: NDSInput.select.rawValue, scale: scale, fill: PadPalette.NDS.shoulder, ink: PadPalette.NDS.ink)
        case .n64:
            EmptyView()
        }
    }

    /// START alone, for the bottom of the right landscape column.
    @ViewBuilder var startButton: some View {
        switch system {
        case .gba:
            PadPillButton(title: "START", bits: GBAInput.start.bits, scale: scale, fill: PadPalette.GBA.startSelect, ink: PadPalette.GBA.ink)
        case .psp:
            PadPillButton(title: "START", bits: PSPInput.start.rawValue, scale: scale, fill: PadPalette.PSP.silver, ink: PadPalette.PSP.chassis)
        case .nds:
            PadPillButton(title: "START", bits: NDSInput.start.rawValue, scale: scale, fill: PadPalette.NDS.shoulder, ink: PadPalette.NDS.ink)
        case .n64:
            PadPillButton(title: "START", bits: N64Input.start.rawValue, scale: scale, fill: PadPalette.N64.start, ink: PadPalette.N64.inkLight)
        }
    }

    // MARK: Helpers

    private func shoulder(_ title: String, _ bits: UInt32, _ fill: Color, _ ink: Color, width: CGFloat = 92) -> some View {
        let widen: CGFloat = portrait && width == 92 ? 112 / 92 : 1
        return PadShoulderButton(
            title: title, bits: bits,
            width: width * widen * scale, height: (portrait ? 48 : 40) * scale,
            fill: fill, ink: ink
        )
    }

    private func pills(select: UInt32, start: UInt32, fill: Color, ink: Color) -> some View {
        HStack(spacing: (portrait ? 28 : 16) * scale) {
            PadPillButton(title: "SELECT", bits: select, scale: pillScale, fill: fill, ink: ink)
            PadPillButton(title: "START", bits: start, scale: pillScale, fill: fill, ink: ink)
        }
    }

    /// Nintendo two-button face: secondary (B) lower-left, primary (A) upper-right on a
    /// steep diagonal (narrow enough for the landscape column), close enough that the
    /// gap between them presses both.
    private func twoButtons(
        primary: (String, UInt32, Color),
        secondary: (String, UInt32, Color),
        diameter: CGFloat,
        ink: Color
    ) -> some View {
        ZStack {
            PadFaceButton(title: secondary.0, bits: secondary.1, diameter: diameter, fill: secondary.2, ink: ink)
                .offset(x: -diameter * 0.4, y: diameter * 0.42)
            PadFaceButton(title: primary.0, bits: primary.1, diameter: diameter, fill: primary.2, ink: ink)
                .offset(x: diameter * 0.4, y: -diameter * 0.42)
        }
        .frame(width: diameter * 1.8, height: diameter * 1.84)
    }
}

extension GBAInput {
    /// Raw value widened for the shared `UInt32` input bitmask.
    var bits: UInt32 { UInt32(rawValue) }
}

/// Background plate colour per system (portrait).
@available(iOS 18.0, *)
extension SystemID {
    var padChassis: Color {
        switch self {
        case .gba: return PadPalette.GBA.chassis
        case .psp: return PadPalette.PSP.chassis
        case .nds: return PadPalette.NDS.chassis
        case .n64: return PadPalette.N64.chassisDark
        }
    }

    var padChassisStroke: Color {
        switch self {
        case .gba: return PadPalette.GBA.chassisStroke
        case .psp: return PadPalette.PSP.chassisStroke
        case .nds: return PadPalette.NDS.chassisStroke
        case .n64: return PadPalette.N64.chassisStroke
        }
    }
}

// MARK: - Portrait

/// Everything below the screen in portrait. Sized from the space it gets: the thumb row
/// fills the width, and controls grow until either the width or the height runs out.
@available(iOS 18.0, *)
struct ConsolePadPortrait: View {
    let system: SystemID
    let size: CGSize

    /// Clear of the rounded corners and the gripping hand.
    static let horizontalInset: CGFloat = 16
    static let verticalInset: CGFloat = 12
    /// Fewest points between the left and right thumb clusters.
    private static let clusterGap: CGFloat = 28
    private static let shoulderGap: CGFloat = 12
    private static let pillGap: CGFloat = 14

    /// Thumb row width and total height at scale 1 (portrait sizes).
    private static func contentSize(_ system: SystemID) -> CGSize {
        // shoulder 48, SELECT/START (26 + 2 × 8 touch padding) × 1.25.
        let fixed: CGFloat = 48 + shoulderGap + pillGap + 52
        switch system {
        case .gba: return CGSize(width: 156 + 78 * 1.8 + clusterGap, height: fixed + 156)
        case .nds: return CGSize(width: 152 + 60 * 2.8 + clusterGap, height: fixed + 60 * 2.8)
        case .psp: return CGSize(width: 144 + 60 * 2.8 + clusterGap, height: fixed + 144 + 18 + 108)
        case .n64: return CGSize(width: 136 + 136 * 1.08 + clusterGap, height: fixed + 108 + 16 + 136)
        }
    }

    static func scale(for system: SystemID, in size: CGSize) -> CGFloat {
        let content = contentSize(system)
        let width = (size.width - 2 * horizontalInset) / content.width
        let height = (size.height - 2 * verticalInset) / content.height
        return min(max(min(width, height), 0.6), 1.35)
    }

    var body: some View {
        let scale = Self.scale(for: system, in: size)
        let pad = ConsolePad(system: system, scale: scale, portrait: true)
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                pad.leftShoulders
                Spacer(minLength: 8)
                pad.rightShoulders
            }
            // Spare height is split evenly above and below the thumb clusters.
            Spacer(minLength: Self.shoulderGap * scale)
            // PSP / N64: the right cluster lines up with the D-pad, as on the hardware.
            HStack(alignment: system == .psp || system == .n64 ? .top : .center) {
                pad.leftMain
                Spacer(minLength: Self.clusterGap * scale)
                pad.rightMain
            }
            Spacer(minLength: Self.pillGap * scale)
            pad.center
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.vertical, Self.verticalInset)
    }
}

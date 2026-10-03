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
    /// Full-size controls: taller shoulders, larger clusters and SELECT / START. Portrait
    /// always uses them; landscape does when the phone's height leaves room.
    var large = false

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
                shoulder("Z", N64Input.z.rawValue, PadPalette.N64.z, PadPalette.N64.inkLight, width: large ? 96 : 84)
                shoulder("L", N64Input.l.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight, width: large ? 56 : 48)
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
                size: (large ? 156 : 150) * scale,
                up: GBAInput.up.bits, down: GBAInput.down.bits,
                left: GBAInput.left.bits, right: GBAInput.right.bits,
                fill: PadPalette.GBA.dpad, heldFill: PadPalette.GBA.dpadHeld
            )
        case .psp:
            // Real PSP: D-pad above, analog nub below.
            VStack(spacing: (large ? 18 : 10) * scale) {
                PadDPad(
                    size: (large ? 144 : 136) * scale,
                    up: PSPInput.up.rawValue, down: PSPInput.down.rawValue,
                    left: PSPInput.left.rawValue, right: PSPInput.right.rawValue,
                    fill: PadPalette.PSP.dpad, heldFill: PadPalette.PSP.nub
                )
                PadStick(
                    size: (large ? 108 : 96) * scale,
                    gateFill: Color(red: 0.16, green: 0.16, blue: 0.17),
                    nubFill: PadPalette.PSP.nub,
                    octagonal: false,
                    accessibilityName: "Analog nub"
                )
            }
        case .nds:
            PadDPad(
                size: (large ? 152 : 146) * scale,
                up: NDSInput.up.rawValue, down: NDSInput.down.rawValue,
                left: NDSInput.left.rawValue, right: NDSInput.right.rawValue,
                fill: PadPalette.NDS.dpad, heldFill: PadPalette.NDS.shoulder
            )
        case .n64:
            // The Control Stick is what N64 games are played with, so it takes the low spot
            // where the thumb rests; the rarely used D-pad sits above it.
            VStack(spacing: (large ? 16 : 10) * scale) {
                PadDPad(
                    size: (large ? 108 : 100) * scale,
                    up: N64Input.dpadUp.rawValue, down: N64Input.dpadDown.rawValue,
                    left: N64Input.dpadLeft.rawValue, right: N64Input.dpadRight.rawValue,
                    fill: PadPalette.N64.dpad, heldFill: PadPalette.N64.chassisDark
                )
                PadStick(
                    size: (large ? 136 : 128) * scale,
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
                diameter: (large ? 78 : 74) * scale,
                ink: PadPalette.GBA.ink
            )
        case .psp:
            PadDiamond(
                top: .init(title: "△", bits: PSPInput.triangle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.triangle, name: "Triangle"),
                right: .init(title: "○", bits: PSPInput.circle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.circle, name: "Circle"),
                bottom: .init(title: "✕", bits: PSPInput.cross.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.cross, name: "Cross"),
                left: .init(title: "□", bits: PSPInput.square.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.square, name: "Square"),
                diameter: (large ? 60 : 54) * scale
            )
        case .nds:
            PadDiamond(
                top: .init(title: "X", bits: NDSInput.x.rawValue, fill: PadPalette.NDS.x, ink: PadPalette.NDS.ink),
                right: .init(title: "A", bits: NDSInput.a.rawValue, fill: PadPalette.NDS.a, ink: PadPalette.NDS.ink),
                bottom: .init(title: "B", bits: NDSInput.b.rawValue, fill: PadPalette.NDS.b, ink: PadPalette.NDS.inkDark),
                left: .init(title: "Y", bits: NDSInput.y.rawValue, fill: PadPalette.NDS.y, ink: PadPalette.NDS.ink),
                diameter: (large ? 60 : 54) * scale
            )
        case .n64:
            VStack(spacing: (large ? 14 : 6) * scale) {
                PadDiamond(
                    top: .init(title: "▲", bits: N64Input.cUp.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Up"),
                    right: .init(title: "▶", bits: N64Input.cRight.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Right"),
                    bottom: .init(title: "▼", bits: N64Input.cDown.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Down"),
                    left: .init(title: "◀", bits: N64Input.cLeft.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Left"),
                    diameter: (large ? 44 : 40) * scale
                )
                // Hardware: green B up-left of the larger blue A.
                let k: CGFloat = large ? 1.08 : 1
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

    /// SELECT / START are easy to miss small; full-size controls get bigger ones.
    private var pillScale: CGFloat { large ? scale * 1.25 : scale }

    // MARK: Landscape columns

    /// Width each landscape side column needs: the wider of its two thumb clusters
    /// (D-pad / stick on the left, face buttons on the right), so a fitted screen
    /// can sit between the columns without anything overlapping it.
    var landscapeColumnWidth: CGFloat {
        if large {
            switch system {
            case .gba: return 156 * scale
            case .psp, .nds: return 168 * scale
            case .n64: return 160 * scale
            }
        }
        switch system {
        case .gba: return 150 * scale
        case .psp, .nds: return 151 * scale
        case .n64: return 140 * scale
        }
    }

    /// Height of the taller landscape side column at scale 1 (shoulders, pause row,
    /// thumb cluster, SELECT / START and the gaps between them), with a little margin.
    private static func landscapeColumnHeight(_ system: SystemID, large: Bool) -> CGFloat {
        switch (system, large) {
        case (.gba, false): return 300
        case (.nds, false): return 315
        case (.psp, false): return 355
        case (.n64, false): return 385
        case (.gba, true): return 326
        case (.nds, true): return 356
        case (.psp, true): return 402
        case (.n64, true): return 437
        }
    }

    /// Landscape controls: the portrait size when the column still fits the phone's height,
    /// else as large as the height allows. Falls back to the compact sizes when those come
    /// out bigger (a tall column, like N64's, on a short phone).
    static func landscapeLayout(
        for system: SystemID,
        in size: CGSize,
        portraitScale: CGFloat
    ) -> (scale: CGFloat, large: Bool) {
        let usable = size.height - 12
        let largeScale = min(portraitScale, usable / landscapeColumnHeight(system, large: true))
        let compactScale = min(max(size.height / 390, 0.66), 1.15, usable / landscapeColumnHeight(system, large: false))
        // Full-size controls are about 7% bigger at the same scale.
        return largeScale * 1.07 >= compactScale ? (largeScale, true) : (compactScale, false)
    }

    /// SELECT alone, for the bottom of the left landscape column (N64 has none).
    @ViewBuilder var selectButton: some View {
        switch system {
        case .gba:
            PadPillButton(title: "SELECT", bits: GBAInput.select.bits, scale: pillScale, fill: PadPalette.GBA.startSelect, ink: PadPalette.GBA.ink)
        case .psp:
            PadPillButton(title: "SELECT", bits: PSPInput.select.rawValue, scale: pillScale, fill: PadPalette.PSP.silver, ink: PadPalette.PSP.chassis)
        case .nds:
            PadPillButton(title: "SELECT", bits: NDSInput.select.rawValue, scale: pillScale, fill: PadPalette.NDS.shoulder, ink: PadPalette.NDS.ink)
        case .n64:
            EmptyView()
        }
    }

    /// START alone, for the bottom of the right landscape column.
    @ViewBuilder var startButton: some View {
        switch system {
        case .gba:
            PadPillButton(title: "START", bits: GBAInput.start.bits, scale: pillScale, fill: PadPalette.GBA.startSelect, ink: PadPalette.GBA.ink)
        case .psp:
            PadPillButton(title: "START", bits: PSPInput.start.rawValue, scale: pillScale, fill: PadPalette.PSP.silver, ink: PadPalette.PSP.chassis)
        case .nds:
            PadPillButton(title: "START", bits: NDSInput.start.rawValue, scale: pillScale, fill: PadPalette.NDS.shoulder, ink: PadPalette.NDS.ink)
        case .n64:
            PadPillButton(title: "START", bits: N64Input.start.rawValue, scale: pillScale, fill: PadPalette.N64.start, ink: PadPalette.N64.inkLight)
        }
    }

    // MARK: Helpers

    private func shoulder(_ title: String, _ bits: UInt32, _ fill: Color, _ ink: Color, width: CGFloat = 92) -> some View {
        let widen: CGFloat = large && width == 92 ? 112 / 92 : 1
        return PadShoulderButton(
            title: title, bits: bits,
            width: width * widen * scale, height: (large ? 48 : 40) * scale,
            fill: fill, ink: ink
        )
    }

    private func pills(select: UInt32, start: UInt32, fill: Color, ink: Color) -> some View {
        HStack(spacing: (large ? 28 : 16) * scale) {
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
        let pad = ConsolePad(system: system, scale: scale, large: true)
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

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
                shoulder("Z", N64Input.z.rawValue, PadPalette.N64.z, PadPalette.N64.inkLight, width: 84)
                shoulder("L", N64Input.l.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight, width: 48)
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
                size: 150 * scale,
                up: GBAInput.up.bits, down: GBAInput.down.bits,
                left: GBAInput.left.bits, right: GBAInput.right.bits,
                fill: PadPalette.GBA.dpad, heldFill: PadPalette.GBA.dpadHeld
            )
        case .psp:
            // Real PSP: D-pad above, analog nub below.
            VStack(spacing: 10 * scale) {
                PadDPad(
                    size: 136 * scale,
                    up: PSPInput.up.rawValue, down: PSPInput.down.rawValue,
                    left: PSPInput.left.rawValue, right: PSPInput.right.rawValue,
                    fill: PadPalette.PSP.dpad, heldFill: PadPalette.PSP.nub
                )
                PadStick(
                    size: 96 * scale,
                    gateFill: Color(red: 0.16, green: 0.16, blue: 0.17),
                    nubFill: PadPalette.PSP.nub,
                    octagonal: false,
                    accessibilityName: "Analog nub"
                )
            }
        case .nds:
            PadDPad(
                size: 146 * scale,
                up: NDSInput.up.rawValue, down: NDSInput.down.rawValue,
                left: NDSInput.left.rawValue, right: NDSInput.right.rawValue,
                fill: PadPalette.NDS.dpad, heldFill: PadPalette.NDS.shoulder
            )
        case .n64:
            // The Control Stick is what N64 games are played with, so it takes the low spot
            // where the thumb rests; the rarely used D-pad sits above it.
            VStack(spacing: 10 * scale) {
                PadDPad(
                    size: 100 * scale,
                    up: N64Input.dpadUp.rawValue, down: N64Input.dpadDown.rawValue,
                    left: N64Input.dpadLeft.rawValue, right: N64Input.dpadRight.rawValue,
                    fill: PadPalette.N64.dpad, heldFill: PadPalette.N64.chassisDark
                )
                PadStick(
                    size: 128 * scale,
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
                diameter: 68 * scale,
                ink: PadPalette.GBA.ink
            )
        case .psp:
            PadDiamond(
                top: .init(title: "△", bits: PSPInput.triangle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.triangle, name: "Triangle"),
                right: .init(title: "○", bits: PSPInput.circle.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.circle, name: "Circle"),
                bottom: .init(title: "✕", bits: PSPInput.cross.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.cross, name: "Cross"),
                left: .init(title: "□", bits: PSPInput.square.rawValue, fill: PadPalette.PSP.face, ink: PadPalette.PSP.square, name: "Square"),
                diameter: 54 * scale
            )
        case .nds:
            PadDiamond(
                top: .init(title: "X", bits: NDSInput.x.rawValue, fill: PadPalette.NDS.x, ink: PadPalette.NDS.ink),
                right: .init(title: "A", bits: NDSInput.a.rawValue, fill: PadPalette.NDS.a, ink: PadPalette.NDS.ink),
                bottom: .init(title: "B", bits: NDSInput.b.rawValue, fill: PadPalette.NDS.b, ink: PadPalette.NDS.inkDark),
                left: .init(title: "Y", bits: NDSInput.y.rawValue, fill: PadPalette.NDS.y, ink: PadPalette.NDS.ink),
                diameter: 54 * scale
            )
        case .n64:
            VStack(spacing: 6 * scale) {
                PadDiamond(
                    top: .init(title: "▲", bits: N64Input.cUp.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Up"),
                    right: .init(title: "▶", bits: N64Input.cRight.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Right"),
                    bottom: .init(title: "▼", bits: N64Input.cDown.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Down"),
                    left: .init(title: "◀", bits: N64Input.cLeft.rawValue, fill: PadPalette.N64.c, ink: PadPalette.N64.inkDark, name: "C Left"),
                    diameter: 40 * scale
                )
                // Hardware: green B up-left of the larger blue A.
                ZStack {
                    PadFaceButton(title: "B", bits: N64Input.b.rawValue, diameter: 56 * scale, fill: PadPalette.N64.b, ink: PadPalette.N64.inkLight)
                        .offset(x: -30 * scale, y: -16 * scale)
                    PadFaceButton(title: "A", bits: N64Input.a.rawValue, diameter: 66 * scale, fill: PadPalette.N64.a, ink: PadPalette.N64.inkLight)
                        .offset(x: 30 * scale, y: 16 * scale)
                }
                .frame(width: 136 * scale, height: 104 * scale)
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
            PadPillButton(title: "START", bits: N64Input.start.rawValue, scale: scale, fill: PadPalette.N64.start, ink: PadPalette.N64.inkLight)
        }
    }

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
        PadShoulderButton(title: title, bits: bits, width: width * scale, height: 40 * scale, fill: fill, ink: ink)
    }

    private func pills(select: UInt32, start: UInt32, fill: Color, ink: Color) -> some View {
        HStack(spacing: 16 * scale) {
            PadPillButton(title: "SELECT", bits: select, scale: scale, fill: fill, ink: ink)
            PadPillButton(title: "START", bits: start, scale: scale, fill: fill, ink: ink)
        }
    }

    /// Nintendo two-button face: secondary (B) lower-left, primary (A) upper-right,
    /// close enough that the gap between them presses both.
    private func twoButtons(
        primary: (String, UInt32, Color),
        secondary: (String, UInt32, Color),
        diameter: CGFloat,
        ink: Color
    ) -> some View {
        ZStack {
            PadFaceButton(title: secondary.0, bits: secondary.1, diameter: diameter, fill: secondary.2, ink: ink)
                .offset(x: -diameter * 0.46, y: diameter * 0.3)
            PadFaceButton(title: primary.0, bits: primary.1, diameter: diameter, fill: primary.2, ink: ink)
                .offset(x: diameter * 0.46, y: -diameter * 0.3)
        }
        .frame(width: diameter * 2.05, height: diameter * 1.7)
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

/// Everything below the screen in portrait.
@available(iOS 18.0, *)
struct ConsolePadPortrait: View {
    let system: SystemID
    let scale: CGFloat

    var body: some View {
        let pad = ConsolePad(system: system, scale: scale)
        VStack(spacing: 8 * scale) {
            HStack(alignment: .top) {
                pad.leftShoulders
                Spacer(minLength: 8)
                pad.rightShoulders
            }
            // Thumbs rest low on the phone: spare height goes above the clusters, and only
            // a small gap separates them from SELECT/START.
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                pad.leftMain
                Spacer(minLength: 4)
                pad.rightMain
            }
            Spacer(minLength: 0)
                .frame(maxHeight: 24 * scale)
            pad.center
        }
        // Clear of the rounded corners and the gripping hand.
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

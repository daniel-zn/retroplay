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
    /// Landscape side columns: gaps inside a cluster are tighter, so full-size
    /// controls fit the phone's height.
    var landscape = false

    // MARK: Shoulders

    @ViewBuilder var leftShoulders: some View {
        switch system {
        case .gba:
            shoulder("L", GBAInput.l.bits, PadPalette.GBA.shoulder, PadPalette.GBA.ink, outer: .leading)
        case .psp:
            shoulder("L", PSPInput.l.rawValue, PadPalette.PSP.nub, PadPalette.PSP.ink, outer: .leading)
        case .nds:
            shoulder("L", NDSInput.l.rawValue, PadPalette.NDS.shoulder, PadPalette.NDS.ink, outer: .leading)
        case .n64:
            // Z is the trigger N64 games lean on (Z-targeting, crouch, shoot); L is rarely
            // used, so Z gets the big button and L sits beside it.
            HStack(spacing: 8 * scale) {
                shoulder("Z", N64Input.z.rawValue, PadPalette.N64.z, PadPalette.N64.inkLight, width: large ? 96 : 84, outer: .leading)
                shoulder("L", N64Input.l.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight, width: large ? 56 : 48)
            }
        case .snes:
            shoulder("L", RetroPadInput.l.rawValue, PadPalette.SNES.shoulder, PadPalette.SNES.inkDark, outer: .leading)
        case .ps1:
            stackedShoulders(
                outer: .leading,
                top: ("L2", RetroPadInput.PS1.l2.rawValue),
                bottom: ("L1", RetroPadInput.PS1.l1.rawValue)
            )
        case .nes, .genesis, .atari7800:
            EmptyView()
        }
    }

    @ViewBuilder var rightShoulders: some View {
        switch system {
        case .gba:
            shoulder("R", GBAInput.r.bits, PadPalette.GBA.shoulder, PadPalette.GBA.ink, outer: .trailing)
        case .psp:
            shoulder("R", PSPInput.r.rawValue, PadPalette.PSP.nub, PadPalette.PSP.ink, outer: .trailing)
        case .nds:
            shoulder("R", NDSInput.r.rawValue, PadPalette.NDS.shoulder, PadPalette.NDS.ink, outer: .trailing)
        case .n64:
            shoulder("R", N64Input.r.rawValue, PadPalette.N64.shoulder, PadPalette.N64.inkLight, outer: .trailing)
        case .snes:
            shoulder("R", RetroPadInput.r.rawValue, PadPalette.SNES.shoulder, PadPalette.SNES.inkDark, outer: .trailing)
        case .ps1:
            stackedShoulders(
                outer: .trailing,
                top: ("R2", RetroPadInput.PS1.r2.rawValue),
                bottom: ("R1", RetroPadInput.PS1.r1.rawValue)
            )
        case .nes, .genesis, .atari7800:
            EmptyView()
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
            VStack(spacing: (large && !landscape ? 18 : landscape ? 6 : 10) * scale) {
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
            VStack(spacing: (large && !landscape ? 16 : landscape ? 6 : 10) * scale) {
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
        case .nes:
            retroDPad(fill: PadPalette.NES.dpad, heldFill: PadPalette.NES.dpadHeld)
        case .snes:
            retroDPad(fill: PadPalette.SNES.dpad, heldFill: PadPalette.SNES.shoulder)
        case .genesis:
            retroDPad(fill: PadPalette.Genesis.dpad, heldFill: PadPalette.Genesis.faceTop)
        case .atari7800:
            // The Pro-Line joystick, as eight-way directions.
            retroDPad(fill: PadPalette.Atari7800.stick, heldFill: PadPalette.Atari7800.stickHeld)
        case .ps1:
            retroDPad(fill: PadPalette.PS1.dpad, heldFill: PadPalette.PS1.shoulder)
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
            VStack(spacing: (large && !landscape ? 14 : 6) * scale) {
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
        case .nes:
            // NES: B and A side by side, A on the right.
            HStack(spacing: Self.nesGap * nesDiameter) {
                PadFaceButton(title: "B", bits: RetroPadInput.NES.b.rawValue, diameter: nesDiameter, fill: PadPalette.NES.face, ink: PadPalette.NES.ink)
                PadFaceButton(title: "A", bits: RetroPadInput.NES.a.rawValue, diameter: nesDiameter, fill: PadPalette.NES.face, ink: PadPalette.NES.ink)
            }
        case .snes:
            PadDiamond(
                top: .init(title: "X", bits: RetroPadInput.SNES.x.rawValue, fill: PadPalette.SNES.x, ink: PadPalette.SNES.ink),
                right: .init(title: "A", bits: RetroPadInput.SNES.a.rawValue, fill: PadPalette.SNES.a, ink: PadPalette.SNES.ink),
                bottom: .init(title: "B", bits: RetroPadInput.SNES.b.rawValue, fill: PadPalette.SNES.b, ink: PadPalette.SNES.inkDark),
                left: .init(title: "Y", bits: RetroPadInput.SNES.y.rawValue, fill: PadPalette.SNES.y, ink: PadPalette.SNES.ink),
                diameter: (large ? 60 : 54) * scale
            )
        case .genesis:
            genesisFace
        case .atari7800:
            twoButtons(
                primary: ("2", RetroPadInput.Atari7800.button2.rawValue, PadPalette.Atari7800.fire),
                secondary: ("1", RetroPadInput.Atari7800.button1.rawValue, PadPalette.Atari7800.fire),
                diameter: (large ? 78 : 74) * scale,
                ink: PadPalette.Atari7800.ink
            )
        case .ps1:
            PadDiamond(
                top: .init(title: "△", bits: RetroPadInput.PS1.triangle.rawValue, fill: PadPalette.PS1.face, ink: PadPalette.PSP.triangle, name: "Triangle"),
                right: .init(title: "○", bits: RetroPadInput.PS1.circle.rawValue, fill: PadPalette.PS1.face, ink: PadPalette.PSP.circle, name: "Circle"),
                bottom: .init(title: "✕", bits: RetroPadInput.PS1.cross.rawValue, fill: PadPalette.PS1.face, ink: PadPalette.PSP.cross, name: "Cross"),
                left: .init(title: "□", bits: RetroPadInput.PS1.square.rawValue, fill: PadPalette.PS1.face, ink: PadPalette.PSP.square, name: "Square"),
                diameter: (large ? 60 : 54) * scale
            )
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
        case .nes:
            pills(select: RetroPadInput.select.rawValue, start: RetroPadInput.start.rawValue, fill: PadPalette.NES.pill, ink: PadPalette.NES.ink)
        case .snes:
            pills(select: RetroPadInput.select.rawValue, start: RetroPadInput.start.rawValue, fill: PadPalette.SNES.pill, ink: PadPalette.SNES.ink)
        case .genesis:
            PadPillButton(title: "START", bits: RetroPadInput.start.rawValue, scale: pillScale, fill: PadPalette.Genesis.start, ink: PadPalette.Genesis.ink)
        case .atari7800:
            // The console's switches; most games start on Reset or Pause.
            HStack(spacing: 14 * scale) {
                atariSwitch("SELECT", RetroPadInput.Atari7800.select)
                atariSwitch("PAUSE", RetroPadInput.Atari7800.pause)
                atariSwitch("RESET", RetroPadInput.Atari7800.reset)
            }
        case .ps1:
            pills(select: RetroPadInput.select.rawValue, start: RetroPadInput.start.rawValue, fill: PadPalette.PS1.pill, ink: PadPalette.PS1.ink)
        }
    }

    /// PSP in landscape: room under the face buttons that lines their centre up with the
    /// D-pad's, which sits above the analog stick in the left column. Measured from each
    /// column's foot: the left one ends in an 8 pt spacer, the right one in the 18 + 32 pt
    /// fast-forward / pause / sound row.
    var landscapeFaceLift: CGFloat {
        guard system == .psp else { return 0 }
        let dpad: CGFloat = large ? 144 : 136
        let stick: CGFloat = large ? 108 : 96
        let diameter: CGFloat = large ? 60 : 54
        let dpadCentre = 8 + (stick + 6 + dpad / 2) * scale
        let faceCentre = 50 + diameter * 1.4 * scale
        return max(0, dpadCentre - faceCentre)
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
            case .nes: return 168 * scale
            case .snes, .ps1: return 168 * scale
            case .genesis: return Self.genesisWidth(78 * 0.74) * scale
            case .atari7800: return 156 * scale
            }
        }
        switch system {
        case .gba: return 150 * scale
        case .psp, .nds: return 151 * scale
        case .n64: return 140 * scale
        case .nes: return 154 * scale
        case .snes, .ps1: return 151 * scale
        case .genesis: return Self.genesisWidth(48) * scale
        case .atari7800: return 150 * scale
        }
    }

    /// Each landscape column's height as `perScale × scale + fixed`: shoulders and thumb
    /// cluster grow with the scale; the edge padding and the pause row don't (SELECT / START
    /// sit at the bottom centre, outside the columns). Mirrors `PlayView.landscapeLayout`.
    private static func landscapeColumns(_ system: SystemID, large: Bool) -> [(perScale: CGFloat, fixed: CGFloat)] {
        // Shoulder height.
        let top: CGFloat = large ? 42 : 40
        // Left: 2 × 6 edge padding + 6 spacer. Right adds the 18 + 32 pause row.
        let left: CGFloat = 18, right: CGFloat = 18 + 50
        let leftCluster: CGFloat, rightCluster: CGFloat
        switch (system, large) {
        case (.gba, false): (leftCluster, rightCluster) = (150, 74 * 1.84)
        case (.gba, true): (leftCluster, rightCluster) = (156, 78 * 1.84)
        case (.nds, false): (leftCluster, rightCluster) = (146, 54 * 2.8)
        case (.nds, true): (leftCluster, rightCluster) = (152, 60 * 2.8)
        // PSP's face buttons are lifted level with the D-pad (`landscapeFaceLift`): from their
        // top, half the diamond, then the D-pad's lower half, the gap and the stick.
        case (.psp, false): (leftCluster, rightCluster) = (136 + 6 + 96, 54 * 1.4 + 68 + 6 + 96)
        case (.psp, true): (leftCluster, rightCluster) = (144 + 6 + 108, 60 * 1.4 + 72 + 6 + 108)
        case (.n64, false): (leftCluster, rightCluster) = (100 + 6 + 128, 40 * 2.8 + 6 + 104)
        case (.n64, true): (leftCluster, rightCluster) = (108 + 6 + 136, 44 * 2.8 + 6 + 108 * 1.08)
        case (.nes, false): (leftCluster, rightCluster) = (150, 70)
        case (.nes, true): (leftCluster, rightCluster) = (156, 76)
        case (.snes, false), (.ps1, false): (leftCluster, rightCluster) = (150, 54 * 2.8)
        case (.snes, true), (.ps1, true): (leftCluster, rightCluster) = (156, 60 * 2.8)
        case (.genesis, false): (leftCluster, rightCluster) = (150, 48 * 1.9)
        case (.genesis, true): (leftCluster, rightCluster) = (156, 78 * 0.74 * 1.9)
        case (.atari7800, false): (leftCluster, rightCluster) = (150, 74 * 1.84)
        case (.atari7800, true): (leftCluster, rightCluster) = (156, 78 * 1.84)
        }
        // Systems without shoulder buttons, and PS1's two stacked rows.
        let shoulders: CGFloat
        switch system {
        case .nes, .genesis, .atari7800: shoulders = 0
        case .ps1: shoulders = 2 * top * psShoulderRatio + 6
        default: shoulders = top
        }
        // PSP: the lift replaces the pause row's height under the face buttons (8 pt foot as
        // on the left instead).
        return [
            (shoulders + leftCluster, left),
            (shoulders + rightCluster, system == .psp ? left + 8 : right),
        ]
    }

    /// Landscape controls: the portrait size when both columns fit the phone's height
    /// (`size` includes the home-indicator strip), else as large as the height allows.
    /// Falls back to the compact sizes when those come out bigger (N64's tall right column).
    static func landscapeLayout(
        for system: SystemID,
        in size: CGSize,
        portraitScale: CGFloat
    ) -> (scale: CGFloat, large: Bool) {
        func fit(_ large: Bool) -> CGFloat {
            landscapeColumns(system, large: large)
                .map { (size.height - $0.fixed - 4) / $0.perScale }
                .min() ?? 1
        }
        let largeScale = min(portraitScale, fit(true))
        let compactScale = min(max(size.height / 390, 0.66), 1.15, fit(false))
        // Full-size controls are about 7% bigger at the same scale.
        return largeScale * 1.07 >= compactScale ? (largeScale, true) : (compactScale, false)
    }

    // MARK: Helpers

    /// The shared D-pad for the libretro systems (RetroPad direction bits).
    private func retroDPad(fill: Color, heldFill: Color) -> some View {
        PadDPad(
            size: (large ? 156 : 150) * scale,
            up: RetroPadInput.up.rawValue, down: RetroPadInput.down.rawValue,
            left: RetroPadInput.left.rawValue, right: RetroPadInput.right.rawValue,
            fill: fill, heldFill: heldFill
        )
    }

    /// NES A/B: diameter, and the gap between them as a fraction of it.
    private var nesDiameter: CGFloat { (large ? 76 : 70) * scale }
    private static let nesGap: CGFloat = 0.2

    /// PS1 shoulders are stacked two high, each a little shorter than a single shoulder.
    private static let psShoulderRatio: CGFloat = 0.85

    private func stackedShoulders(outer: HorizontalEdge, top: (String, UInt32), bottom: (String, UInt32)) -> some View {
        VStack(spacing: 6 * scale) {
            shoulder(top.0, top.1, PadPalette.PS1.shoulder, PadPalette.PS1.ink, heightRatio: Self.psShoulderRatio, outer: outer)
            shoulder(bottom.0, bottom.1, PadPalette.PS1.shoulder, PadPalette.PS1.ink, heightRatio: Self.psShoulderRatio)
        }
    }

    /// Genesis six-button face: A B C along the bottom, the smaller X Y Z above, both rows
    /// rising to the right as on the pad.
    private var genesisFace: some View {
        let d = (large ? 78 * 0.74 : 48) * scale
        let top = d * 0.72
        let gap = d * 0.16
        func button(_ title: String, _ bits: RetroPadInput, _ diameter: CGFloat, _ fill: Color) -> some View {
            PadFaceButton(title: title, bits: bits.rawValue, diameter: diameter, fill: fill, ink: PadPalette.Genesis.ink)
        }
        return VStack(alignment: .trailing, spacing: d * 0.18) {
            HStack(alignment: .bottom, spacing: gap + (d - top)) {
                button("X", RetroPadInput.Genesis.x, top, PadPalette.Genesis.faceTop)
                    .offset(y: d * 0.1)
                button("Y", RetroPadInput.Genesis.y, top, PadPalette.Genesis.faceTop)
                button("Z", RetroPadInput.Genesis.z, top, PadPalette.Genesis.faceTop)
                    .offset(y: -d * 0.1)
            }
            .padding(.trailing, (d - top) / 2)
            HStack(spacing: gap) {
                button("A", RetroPadInput.Genesis.a, d, PadPalette.Genesis.face)
                    .offset(y: d * 0.1)
                button("B", RetroPadInput.Genesis.b, d, PadPalette.Genesis.face)
                button("C", RetroPadInput.Genesis.c, d, PadPalette.Genesis.face)
                    .offset(y: -d * 0.1)
            }
        }
        .frame(width: Self.genesisWidth(d), height: d * 1.9)
    }

    /// Width of the Genesis face for a bottom-row diameter `d` (three buttons, two gaps).
    static func genesisWidth(_ d: CGFloat) -> CGFloat { d * 3.32 }

    private func atariSwitch(_ title: String, _ bits: RetroPadInput) -> some View {
        PadPillButton(title: title, bits: bits.rawValue, scale: pillScale, fill: PadPalette.Atari7800.switchFill, ink: PadPalette.Atari7800.inkDark)
    }

    private func shoulder(
        _ title: String, _ bits: UInt32, _ fill: Color, _ ink: Color,
        width: CGFloat = 92, heightRatio: CGFloat = 1, outer: HorizontalEdge? = nil
    ) -> some View {
        let widen: CGFloat = large && width == 92 ? 112 / 92 : 1
        return PadShoulderButton(
            title: title, bits: bits,
            width: width * widen * scale,
            height: (large ? (landscape ? 42 : 48) : 40) * heightRatio * scale,
            fill: fill, ink: ink, outer: outer
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
        case .nes: return PadPalette.NES.chassis
        case .snes: return PadPalette.SNES.chassis
        case .genesis: return PadPalette.Genesis.chassis
        case .atari7800: return PadPalette.Atari7800.chassis
        case .ps1: return PadPalette.PS1.chassis
        }
    }

    var padChassisStroke: Color {
        switch self {
        case .gba: return PadPalette.GBA.chassisStroke
        case .psp: return PadPalette.PSP.chassisStroke
        case .nds: return PadPalette.NDS.chassisStroke
        case .n64: return PadPalette.N64.chassisStroke
        case .nes: return PadPalette.NES.chassisStroke
        case .snes: return PadPalette.SNES.chassisStroke
        case .genesis: return PadPalette.Genesis.chassisStroke
        case .atari7800: return PadPalette.Atari7800.chassisStroke
        case .ps1: return PadPalette.PS1.chassisStroke
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
    /// The controls' distance from the backing (inset 6 pt from the screen's sides) on every
    /// side, so the shoulders sit as far from its top as from its sides.
    static let edgeInset: CGFloat = 10
    static let verticalInset: CGFloat = edgeInset
    /// Fewest points between the left and right thumb clusters.
    private static let clusterGap: CGFloat = 28
    private static let shoulderGap: CGFloat = 12
    private static let pillGap: CGFloat = 14

    /// Thumb row width and total height at scale 1 (portrait sizes).
    private static func contentSize(_ system: SystemID) -> CGSize {
        // shoulder 48, SELECT/START (26 + 2 × 8 touch padding) × 1.25.
        let fixed: CGFloat = 48 + shoulderGap + pillGap + 52
        // NES, Genesis and the 7800 have no shoulder buttons; PS1 stacks two rows.
        let noShoulders = fixed - 48
        let psShoulders = noShoulders + 2 * 48 * 0.85 + 6
        switch system {
        case .gba: return CGSize(width: 156 + 78 * 1.8 + clusterGap, height: fixed + 156)
        case .nds: return CGSize(width: 152 + 60 * 2.8 + clusterGap, height: fixed + 60 * 2.8)
        case .psp: return CGSize(width: 144 + 60 * 2.8 + clusterGap, height: fixed + 144 + 18 + 108)
        case .n64: return CGSize(width: 136 + 136 * 1.08 + clusterGap, height: fixed + 108 + 16 + 136)
        case .nes: return CGSize(width: 156 + 76 * 2.2 + clusterGap, height: noShoulders + 156)
        case .snes: return CGSize(width: 156 + 60 * 2.8 + clusterGap, height: fixed + 60 * 2.8)
        case .genesis:
            return CGSize(width: 156 + ConsolePad.genesisWidth(78 * 0.74) + clusterGap, height: noShoulders + 156)
        case .atari7800: return CGSize(width: 156 + 78 * 1.8 + clusterGap, height: noShoulders + 156)
        case .ps1: return CGSize(width: 156 + 60 * 2.8 + clusterGap, height: psShoulders + 60 * 2.8)
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

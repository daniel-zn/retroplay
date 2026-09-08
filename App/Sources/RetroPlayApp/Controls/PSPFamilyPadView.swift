import SwiftUI
import RetroPlayCore

/// Portrait and landscape PSP layouts: L/R, D-pad above analog nub stub, △○✕□, Home/Select/Start.
@available(iOS 18.0, *)
struct PSPFamilyPadView: View {
    enum Orientation {
        case portrait
        case landscape
    }

    let orientation: Orientation
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        switch orientation {
        case .portrait:
            portraitPad
        case .landscape:
            landscapePad
        }
    }

    /// Portrait: black/silver slab under the 16:9 frame.
    private var portraitPad: some View {
        PadChassis(fill: PadPalette.PSP.chassis, stroke: PadPalette.PSP.chassisStroke, cornerRadius: 18) {
            VStack(spacing: 10) {
                HStack {
                    PadShoulderButton(
                        title: "L",
                        isHeld: held.contains(.l),
                        width: 78,
                        fill: PadPalette.PSP.nub,
                        ink: PadPalette.PSP.ink,
                        onHeld: { setHeld(.l, $0) }
                    )
                    Spacer()
                    PadShoulderButton(
                        title: "R",
                        isHeld: held.contains(.r),
                        width: 78,
                        fill: PadPalette.PSP.nub,
                        ink: PadPalette.PSP.ink,
                        onHeld: { setHeld(.r, $0) }
                    )
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 8) {
                        // Real PSP: D-pad above, analog nub below on the left.
                        PSPDPadView(held: held, arm: 44, setHeld: setHeld)
                        AnalogStickWell(
                            wellSize: 56,
                            x: 0,
                            y: 0,
                            wellFill: Color(red: 0.16, green: 0.16, blue: 0.17),
                            nubFill: PadPalette.PSP.nub,
                            interactive: false,
                            accessibilityName: "Analog nub",
                            onChange: { _, _ in }
                        )
                    }
                    Spacer(minLength: 4)
                    PSPFaceCluster(held: held, diameter: 44, setHeld: setHeld)
                }

                PSPPadStartSelectRow(held: held, setHeld: setHeld, includeHome: true)
            }
        }
        .accessibilityLabel("PSP controls")
    }

    private var landscapePad: some View {
        HStack(alignment: .center, spacing: 16) {
            PSPPadLeftColumn(held: held, setHeld: setHeld)
            Spacer(minLength: 12)
            PSPPadStartSelectRow(held: held, setHeld: setHeld, includeHome: true)
            Spacer(minLength: 12)
            PSPPadRightColumn(held: held, setHeld: setHeld)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("PSP controls")
    }
}

/// Sony face diamond: △ top, ○ right, ✕ bottom, □ left.
@available(iOS 18.0, *)
struct PSPFaceCluster: View {
    let held: PSPInput
    let diameter: CGFloat
    let setHeld: PSPHeldHandler

    private var reach: CGFloat { diameter * 0.82 }

    private var clusterSide: CGFloat {
        reach * 2 + diameter + 4
    }

    var body: some View {
        ZStack {
            PSPHoldPadButton(
                title: "△",
                bit: .triangle,
                isHeld: held.contains(.triangle),
                diameter: diameter,
                fill: PadPalette.PSP.face,
                ink: PadPalette.PSP.triangle,
                setHeld: setHeld
            )
            .offset(x: 0, y: -reach)
            PSPHoldPadButton(
                title: "○",
                bit: .circle,
                isHeld: held.contains(.circle),
                diameter: diameter,
                fill: PadPalette.PSP.face,
                ink: PadPalette.PSP.circle,
                setHeld: setHeld
            )
            .offset(x: reach, y: 0)
            PSPHoldPadButton(
                title: "✕",
                bit: .cross,
                isHeld: held.contains(.cross),
                diameter: diameter,
                fill: PadPalette.PSP.face,
                ink: PadPalette.PSP.cross,
                setHeld: setHeld
            )
            .offset(x: 0, y: reach)
            PSPHoldPadButton(
                title: "□",
                bit: .square,
                isHeld: held.contains(.square),
                diameter: diameter,
                fill: PadPalette.PSP.face,
                ink: PadPalette.PSP.square,
                setHeld: setHeld
            )
            .offset(x: -reach, y: 0)
        }
        .frame(width: clusterSide, height: clusterSide)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Face buttons")
    }
}

@available(iOS 18.0, *)
struct PSPPadLeftColumn: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        VStack(spacing: 10) {
            PadShoulderButton(
                title: "L",
                isHeld: held.contains(.l),
                width: 64,
                fill: PadPalette.PSP.nub,
                ink: PadPalette.PSP.ink,
                onHeld: { setHeld(.l, $0) }
            )
            // Real PSP: D-pad above, analog nub below on the left.
            PSPDPadView(held: held, arm: 42, setHeld: setHeld)
            AnalogStickWell(
                wellSize: 48,
                x: 0,
                y: 0,
                wellFill: Color(red: 0.16, green: 0.16, blue: 0.17),
                nubFill: PadPalette.PSP.nub,
                interactive: false,
                accessibilityName: "Analog nub",
                onChange: { _, _ in }
            )
            Spacer(minLength: 0)
        }
        .frame(minWidth: 148, maxWidth: 168)
        .padding(.leading, 4)
    }
}

@available(iOS 18.0, *)
struct PSPPadRightColumn: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        VStack(spacing: 14) {
            PadShoulderButton(
                title: "R",
                isHeld: held.contains(.r),
                width: 64,
                fill: PadPalette.PSP.nub,
                ink: PadPalette.PSP.ink,
                onHeld: { setHeld(.r, $0) }
            )
            PSPFaceCluster(held: held, diameter: 42, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 168, maxWidth: 200)
        .padding(.trailing, 10)
    }
}

@available(iOS 18.0, *)
struct PSPPadStartSelectRow: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler
    var includeHome: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            if includeHome {
                PadOvalButton(
                    title: "HOME",
                    isHeld: false,
                    minWidth: 56,
                    minHeight: 40,
                    fill: PadPalette.PSP.silver,
                    ink: PadPalette.PSP.chassis,
                    interactive: false,
                    onHeld: { _ in }
                )
            }
            PSPHoldPadCapsule(title: "SELECT", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            PSPHoldPadCapsule(title: "START", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

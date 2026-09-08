import SwiftUI
import RetroPlayCore

/// Portrait and landscape PSP layouts: L/R, D-pad, Start/Select, △○✕□ face.
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

    /// Portrait: shoulders, then D-pad | face with room, Start/Select under.
    private var portraitPad: some View {
        VStack(spacing: 12) {
            HStack {
                PSPHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 44, setHeld: setHeld)
                Spacer()
                PSPHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 44, setHeld: setHeld)
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 24) {
                PSPDPadView(held: held, arm: 44, setHeld: setHeld)
                Spacer(minLength: 4)
                PSPFaceCluster(held: held, diameter: 42, setHeld: setHeld)
            }
            .padding(.horizontal, 4)

            PSPPadStartSelectRow(held: held, setHeld: setHeld)
        }
        .padding(.vertical, 4)
        .accessibilityLabel("PSP controls")
    }

    /// Landscape strip used when PlayView hosts left/right columns itself.
    /// Kept for ConsolePadHost(.landscape); Play prefers column pieces.
    private var landscapePad: some View {
        HStack(alignment: .center, spacing: 16) {
            PSPPadLeftColumn(held: held, setHeld: setHeld)
            Spacer(minLength: 12)
            PSPPadStartSelectRow(held: held, setHeld: setHeld)
            Spacer(minLength: 12)
            PSPPadRightColumn(held: held, setHeld: setHeld)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("PSP controls")
    }
}

/// Sony face diamond: △ top, ○ right, ✕ bottom, □ left.
/// Center-to-center offset ≥ diameter so circles do not overlap (plus a small gap).
@available(iOS 18.0, *)
struct PSPFaceCluster: View {
    let held: PSPInput
    let diameter: CGFloat
    let setHeld: PSPHeldHandler

    /// Distance from cluster center to each button center.
    private var reach: CGFloat {
        // diameter/2 + diameter/2 + gap ≈ diameter + gap
        diameter * 0.82
    }

    private var clusterSide: CGFloat {
        // Two reaches + full button diameter, with a little padding.
        reach * 2 + diameter + 4
    }

    var body: some View {
        ZStack {
            PSPHoldPadButton(title: "△", bit: .triangle, isHeld: held.contains(.triangle), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: -reach)
            PSPHoldPadButton(title: "○", bit: .circle, isHeld: held.contains(.circle), diameter: diameter, setHeld: setHeld)
                .offset(x: reach, y: 0)
            PSPHoldPadButton(title: "✕", bit: .cross, isHeld: held.contains(.cross), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: reach)
            PSPHoldPadButton(title: "□", bit: .square, isHeld: held.contains(.square), diameter: diameter, setHeld: setHeld)
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
        VStack(spacing: 14) {
            PSPHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 44, setHeld: setHeld)
            PSPDPadView(held: held, arm: 44, setHeld: setHeld)
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
            PSPHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 44, setHeld: setHeld)
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

    var body: some View {
        HStack(spacing: 20) {
            PSPHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            PSPHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

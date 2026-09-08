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

    private var portraitPad: some View {
        VStack(spacing: 14) {
            HStack {
                PSPHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
                Spacer()
                PSPHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 12) {
                PSPDPadView(held: held, arm: 48, setHeld: setHeld)
                Spacer(minLength: 4)
                VStack(spacing: 10) {
                    PSPHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
                    PSPHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
                }
                Spacer(minLength: 4)
                PSPFaceCluster(held: held, diameter: 52, setHeld: setHeld)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .accessibilityLabel("PSP controls")
    }

    private var landscapePad: some View {
        HStack(alignment: .top) {
            VStack(spacing: 10) {
                PSPHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
                PSPDPadView(held: held, arm: 46, setHeld: setHeld)
            }
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                PSPHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
                PSPHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
            }
            .padding(.top, 24)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                PSPHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
                PSPFaceCluster(held: held, diameter: 50, setHeld: setHeld)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("PSP controls")
    }
}

/// Sony face order: △ top, ○ right, ✕ bottom, □ left.
@available(iOS 18.0, *)
struct PSPFaceCluster: View {
    let held: PSPInput
    let diameter: CGFloat
    let setHeld: PSPHeldHandler

    var body: some View {
        ZStack {
            PSPHoldPadButton(title: "△", bit: .triangle, isHeld: held.contains(.triangle), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: -diameter * 0.55)
            PSPHoldPadButton(title: "○", bit: .circle, isHeld: held.contains(.circle), diameter: diameter, setHeld: setHeld)
                .offset(x: diameter * 0.55, y: 0)
            PSPHoldPadButton(title: "✕", bit: .cross, isHeld: held.contains(.cross), diameter: diameter, setHeld: setHeld)
                .offset(x: 0, y: diameter * 0.55)
            PSPHoldPadButton(title: "□", bit: .square, isHeld: held.contains(.square), diameter: diameter, setHeld: setHeld)
                .offset(x: -diameter * 0.55, y: 0)
        }
        .frame(width: diameter * 2.3, height: diameter * 2.3)
    }
}

@available(iOS 18.0, *)
struct PSPPadLeftColumn: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            PSPHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
            PSPDPadView(held: held, arm: 46, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 160)
    }
}

@available(iOS 18.0, *)
struct PSPPadRightColumn: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            PSPHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
            PSPFaceCluster(held: held, diameter: 50, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 170)
    }
}

@available(iOS 18.0, *)
struct PSPPadStartSelectRow: View {
    let held: PSPInput
    let setHeld: PSPHeldHandler

    var body: some View {
        HStack(spacing: 16) {
            PSPHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            PSPHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

import SwiftUI
import RetroPlayCore

/// Portrait-first N64 pad: L/Z/R, D-pad + stick, Start, A/B + C cluster.
@available(iOS 18.0, *)
struct N64FamilyPadView: View {
    enum Orientation {
        case portrait
        case landscape
    }

    let orientation: Orientation
    let held: N64Input
    let setHeld: N64HeldHandler
    let stick: N64AnalogStick
    let setStick: @MainActor @Sendable (N64AnalogStick) -> Void

    var body: some View {
        switch orientation {
        case .portrait:
            portraitPad
        case .landscape:
            landscapePad
        }
    }

    private var portraitPad: some View {
        VStack(spacing: 10) {
            HStack {
                N64HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 42, setHeld: setHeld)
                Spacer()
                N64HoldPadButton(title: "Z", bit: .z, isHeld: held.contains(.z), diameter: 42, setHeld: setHeld)
                Spacer()
                N64HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 42, setHeld: setHeld)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .center, spacing: 10) {
                VStack(spacing: 8) {
                    N64DPadView(held: held, arm: 40, setHeld: setHeld)
                    N64StickPad(stick: stick, setStick: setStick, arm: 36)
                }
                Spacer(minLength: 4)
                VStack(spacing: 10) {
                    N64HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
                    faceCluster(diameter: 48)
                    N64CCluster(held: held, diameter: 34, setHeld: setHeld)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("N64 controls")
    }

    private var landscapePad: some View {
        HStack(alignment: .center, spacing: 12) {
            N64PadLeftColumn(held: held, stick: stick, setHeld: setHeld, setStick: setStick)
            Spacer(minLength: 8)
            N64HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
            Spacer(minLength: 8)
            N64PadRightColumn(held: held, setHeld: setHeld)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityLabel("N64 controls")
    }

    /// Nintendo face: B lower-left, A upper-right.
    private func faceCluster(diameter: CGFloat) -> some View {
        ZStack {
            N64HoldPadButton(title: "B", bit: .b, isHeld: held.contains(.b), diameter: diameter, setHeld: setHeld)
                .offset(x: -diameter * 0.42, y: diameter * 0.28)
            N64HoldPadButton(title: "A", bit: .a, isHeld: held.contains(.a), diameter: diameter, setHeld: setHeld)
                .offset(x: diameter * 0.42, y: -diameter * 0.28)
        }
        .frame(width: diameter * 2.1, height: diameter * 2.0)
    }
}

@available(iOS 18.0, *)
struct N64PadLeftColumn: View {
    let held: N64Input
    let stick: N64AnalogStick
    let setHeld: N64HeldHandler
    let setStick: @MainActor @Sendable (N64AnalogStick) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                N64HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 40, setHeld: setHeld)
                N64HoldPadButton(title: "Z", bit: .z, isHeld: held.contains(.z), diameter: 40, setHeld: setHeld)
            }
            N64DPadView(held: held, arm: 40, setHeld: setHeld)
            N64StickPad(stick: stick, setStick: setStick, arm: 34)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 140, maxWidth: 168)
    }
}

@available(iOS 18.0, *)
struct N64PadRightColumn: View {
    let held: N64Input
    let setHeld: N64HeldHandler

    var body: some View {
        VStack(spacing: 10) {
            N64HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 40, setHeld: setHeld)
            ZStack {
                N64HoldPadButton(title: "B", bit: .b, isHeld: held.contains(.b), diameter: 48, setHeld: setHeld)
                    .offset(x: -20, y: 14)
                N64HoldPadButton(title: "A", bit: .a, isHeld: held.contains(.a), diameter: 48, setHeld: setHeld)
                    .offset(x: 20, y: -14)
            }
            .frame(width: 100, height: 96)
            N64CCluster(held: held, diameter: 32, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 160, maxWidth: 200)
    }
}

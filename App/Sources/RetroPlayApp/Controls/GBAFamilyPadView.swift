import SwiftUI
import RetroPlayCore

/// Portrait (Game Boy–style) and landscape (GBA slab–style) layouts for the GBA family.
@available(iOS 18.0, *)
struct GBAFamilyPadView: View {
    enum Orientation {
        case portrait
        case landscape
    }

    let orientation: Orientation
    let held: GBAInput
    let setHeld: GBAHeldHandler

    var body: some View {
        switch orientation {
        case .portrait:
            portraitPad
        case .landscape:
            landscapePad
        }
    }

    // MARK: - Portrait (controls under screen)

    private var portraitPad: some View {
        VStack(spacing: 14) {
            HStack {
                HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
                Spacer()
                HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 12) {
                DPadView(held: held, arm: 50, setHeld: setHeld)
                Spacer(minLength: 4)
                VStack(spacing: 10) {
                    HoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
                    HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
                }
                Spacer(minLength: 4)
                faceCluster(diameter: 58)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .accessibilityLabel("GBA controls")
    }

    // MARK: - Landscape (self-contained strip)

    private var landscapePad: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(spacing: 10) {
                    HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
                    DPadView(held: held, arm: 48, setHeld: setHeld)
                }
                Spacer(minLength: 8)
                VStack(spacing: 12) {
                    HoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
                    HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
                }
                .padding(.top, 24)
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
                    faceCluster(diameter: 56)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("GBA controls")
    }

    /// Nintendo-style face: B lower-left, A upper-right.
    private func faceCluster(diameter: CGFloat) -> some View {
        ZStack {
            HoldPadButton(
                title: "B",
                bit: .b,
                isHeld: held.contains(.b),
                diameter: diameter,
                setHeld: setHeld
            )
            .offset(x: -diameter * 0.42, y: diameter * 0.28)

            HoldPadButton(
                title: "A",
                bit: .a,
                isHeld: held.contains(.a),
                diameter: diameter,
                setHeld: setHeld
            )
            .offset(x: diameter * 0.42, y: -diameter * 0.28)
        }
        .frame(width: diameter * 2.1, height: diameter * 2.0)
    }
}

// MARK: - Landscape Play shell pieces (Views stay @MainActor; avoids static sendability traps)

@available(iOS 18.0, *)
struct GBAPadLeftColumn: View {
    let held: GBAInput
    let setHeld: GBAHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
            DPadView(held: held, arm: 48, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 160)
    }
}

@available(iOS 18.0, *)
struct GBAPadRightColumn: View {
    let held: GBAInput
    let setHeld: GBAHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
            GBAFaceCluster(held: held, diameter: 56, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 160)
    }
}

@available(iOS 18.0, *)
struct GBAPadStartSelectRow: View {
    let held: GBAInput
    let setHeld: GBAHeldHandler

    var body: some View {
        HStack(spacing: 16) {
            HoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

@available(iOS 18.0, *)
struct GBAFaceCluster: View {
    let held: GBAInput
    let diameter: CGFloat
    let setHeld: GBAHeldHandler

    var body: some View {
        ZStack {
            HoldPadButton(title: "B", bit: .b, isHeld: held.contains(.b), diameter: diameter, setHeld: setHeld)
                .offset(x: -diameter * 0.42, y: diameter * 0.28)
            HoldPadButton(title: "A", bit: .a, isHeld: held.contains(.a), diameter: diameter, setHeld: setHeld)
                .offset(x: diameter * 0.42, y: -diameter * 0.28)
        }
        .frame(width: diameter * 2.1, height: diameter * 2.0)
    }
}

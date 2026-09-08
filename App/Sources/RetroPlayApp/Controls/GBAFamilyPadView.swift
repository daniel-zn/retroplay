import SwiftUI
import RetroPlayCore

/// Portrait (GBA slab mapped under-screen) and landscape overlay for the GBA family.
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
        PadChassis(fill: PadPalette.GBA.chassis, stroke: PadPalette.GBA.chassisStroke, cornerRadius: 28) {
            VStack(spacing: 12) {
                HStack {
                    PadShoulderButton(
                        title: "L",
                        isHeld: held.contains(.l),
                        fill: PadPalette.GBA.shoulder,
                        ink: PadPalette.GBA.ink,
                        onHeld: { setHeld(.l, $0) }
                    )
                    Spacer()
                    PadShoulderButton(
                        title: "R",
                        isHeld: held.contains(.r),
                        fill: PadPalette.GBA.shoulder,
                        ink: PadPalette.GBA.ink,
                        onHeld: { setHeld(.r, $0) }
                    )
                }

                HStack(alignment: .center, spacing: 8) {
                    DPadView(held: held, arm: 48, setHeld: setHeld)
                    Spacer(minLength: 2)
                    startSelectPair
                    Spacer(minLength: 2)
                    faceCluster(diameter: 54)
                }
            }
        }
        .accessibilityLabel("GBA controls")
    }

    // MARK: - Landscape

    private var landscapePad: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                PadShoulderButton(
                    title: "L",
                    isHeld: held.contains(.l),
                    fill: PadPalette.GBA.shoulder,
                    ink: PadPalette.GBA.ink,
                    onHeld: { setHeld(.l, $0) }
                )
                DPadView(held: held, arm: 46, setHeld: setHeld)
            }
            Spacer(minLength: 6)
            startSelectPair
                .padding(.top, 28)
            Spacer(minLength: 6)
            VStack(spacing: 10) {
                PadShoulderButton(
                    title: "R",
                    isHeld: held.contains(.r),
                    fill: PadPalette.GBA.shoulder,
                    ink: PadPalette.GBA.ink,
                    onHeld: { setHeld(.r, $0) }
                )
                faceCluster(diameter: 52)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel("GBA controls")
    }

    /// Nintendo-style face: B lower-left, A upper-right.
    private func faceCluster(diameter: CGFloat) -> some View {
        GBAFaceCluster(held: held, diameter: diameter, setHeld: setHeld)
    }

    /// GBA SELECT / START sit between D-pad and A/B, slightly tilted toward each other.
    private var startSelectPair: some View {
        VStack(spacing: 14) {
            HoldPadCapsule(
                title: "SELECT",
                bit: .select,
                isHeld: held.contains(.select),
                rotation: .degrees(-16),
                setHeld: setHeld
            )
            HoldPadCapsule(
                title: "START",
                bit: .start,
                isHeld: held.contains(.start),
                rotation: .degrees(16),
                setHeld: setHeld
            )
        }
        .frame(width: 78)
    }
}

// MARK: - Landscape Play shell pieces

@available(iOS 18.0, *)
struct GBAPadLeftColumn: View {
    let held: GBAInput
    let setHeld: GBAHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            PadShoulderButton(
                title: "L",
                isHeld: held.contains(.l),
                fill: PadPalette.GBA.shoulder,
                ink: PadPalette.GBA.ink,
                onHeld: { setHeld(.l, $0) }
            )
            DPadView(held: held, arm: 46, setHeld: setHeld)
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
            PadShoulderButton(
                title: "R",
                isHeld: held.contains(.r),
                fill: PadPalette.GBA.shoulder,
                ink: PadPalette.GBA.ink,
                onHeld: { setHeld(.r, $0) }
            )
            GBAFaceCluster(held: held, diameter: 54, setHeld: setHeld)
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
        HStack(spacing: 18) {
            HoldPadCapsule(title: "SELECT", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            HoldPadCapsule(title: "START", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
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
            HoldPadButton(
                title: "B",
                bit: .b,
                isHeld: held.contains(.b),
                diameter: diameter,
                fill: PadPalette.GBA.face,
                setHeld: setHeld
            )
            .offset(x: -diameter * 0.42, y: diameter * 0.28)

            HoldPadButton(
                title: "A",
                bit: .a,
                isHeld: held.contains(.a),
                diameter: diameter,
                fill: PadPalette.GBA.faceA,
                setHeld: setHeld
            )
            .offset(x: diameter * 0.42, y: -diameter * 0.28)
        }
        .frame(width: diameter * 2.1, height: diameter * 2.0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Face buttons")
    }
}

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
    let setHeld: (GBAInput, Bool) -> Void

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

    // MARK: - Landscape (left D-pad / right face; shoulders at top)

    /// Used when PlayView places left and right columns itself; this is a compact
    /// full-width strip for landscape bottom chrome (Start/Select) or a self-contained
    /// landscape pad when embedded in a narrow column stack.
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

/// Split pieces for landscape Play shell (left / right / bottom).
@available(iOS 18.0, *)
enum GBAFamilyPadParts {
    @ViewBuilder
    static func leftColumn(held: GBAInput, setHeld: @escaping (GBAInput, Bool) -> Void) -> some View {
        VStack(spacing: 12) {
            HoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 48, setHeld: setHeld)
            DPadView(held: held, arm: 48, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 160)
    }

    @ViewBuilder
    static func rightColumn(held: GBAInput, setHeld: @escaping (GBAInput, Bool) -> Void) -> some View {
        VStack(spacing: 12) {
            HoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 48, setHeld: setHeld)
            faceAB(held: held, diameter: 56, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 160)
    }

    @ViewBuilder
    static func startSelectRow(held: GBAInput, setHeld: @escaping (GBAInput, Bool) -> Void) -> some View {
        HStack(spacing: 16) {
            HoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            HoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }

    @ViewBuilder
    private static func faceAB(
        held: GBAInput,
        diameter: CGFloat,
        setHeld: @escaping (GBAInput, Bool) -> Void
    ) -> some View {
        ZStack {
            HoldPadButton(title: "B", bit: .b, isHeld: held.contains(.b), diameter: diameter, setHeld: setHeld)
                .offset(x: -diameter * 0.42, y: diameter * 0.28)
            HoldPadButton(title: "A", bit: .a, isHeld: held.contains(.a), diameter: diameter, setHeld: setHeld)
                .offset(x: diameter * 0.42, y: -diameter * 0.28)
        }
        .frame(width: diameter * 2.1, height: diameter * 2.0)
    }
}

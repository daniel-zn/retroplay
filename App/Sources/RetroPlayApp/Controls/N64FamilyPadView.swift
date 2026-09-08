import SwiftUI
import RetroPlayCore

/// Portrait-first N64 trident: D-pad | stick+Start+Z | C cluster + A/B.
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
        tridentBody
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background { tridentPlate }
            .accessibilityLabel("N64 controls")
    }

    private var tridentBody: some View {
        HStack(alignment: .top, spacing: 6) {
            // Left prong: L + Control Pad
            VStack(spacing: 8) {
                PadShoulderButton(
                    title: "L",
                    isHeld: held.contains(.l),
                    width: 64,
                    fill: PadPalette.N64.shoulder,
                    ink: PadPalette.N64.inkLight,
                    onHeld: { setHeld(.l, $0) }
                )
                N64DPadView(held: held, arm: 44, setHeld: setHeld)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            // Center prong: START, Control Stick, Z trigger
            VStack(spacing: 8) {
                N64HoldPadCapsule(
                    title: "START",
                    bit: .start,
                    isHeld: held.contains(.start),
                    setHeld: setHeld
                )
                N64StickPad(stick: stick, setStick: setStick, wellSize: 88)
                PadShoulderButton(
                    title: "Z",
                    isHeld: held.contains(.z),
                    width: 88,
                    height: 44,
                    fill: PadPalette.N64.z,
                    ink: PadPalette.N64.inkLight,
                    onHeld: { setHeld(.z, $0) }
                )
            }
            .frame(maxWidth: .infinity)

            // Right prong: R, C diamond, A (blue) / B (green)
            VStack(spacing: 6) {
                PadShoulderButton(
                    title: "R",
                    isHeld: held.contains(.r),
                    width: 64,
                    fill: PadPalette.N64.shoulder,
                    ink: PadPalette.N64.inkLight,
                    onHeld: { setHeld(.r, $0) }
                )
                N64CCluster(held: held, diameter: 42, setHeld: setHeld)
                n64ABCluster
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// B green, above-left of larger blue A — hardware right-prong pair.
    private var n64ABCluster: some View {
        ZStack {
            N64HoldPadButton(
                title: "B",
                bit: .b,
                isHeld: held.contains(.b),
                diameter: 48,
                fill: PadPalette.N64.b,
                ink: PadPalette.N64.inkLight,
                setHeld: setHeld
            )
            .offset(x: -22, y: -6)
            N64HoldPadButton(
                title: "A",
                bit: .a,
                isHeld: held.contains(.a),
                diameter: 56,
                fill: PadPalette.N64.a,
                ink: PadPalette.N64.inkLight,
                setHeld: setHeld
            )
            .offset(x: 22, y: 10)
        }
        .frame(width: 110, height: 86)
    }

    private var tridentPlate: some View {
        HStack(alignment: .bottom, spacing: 6) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PadPalette.N64.chassis)
                .padding(.top, 32)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PadPalette.N64.chassis)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PadPalette.N64.chassis)
                .padding(.top, 16)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(PadPalette.N64.chassisStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    private var landscapePad: some View {
        HStack(alignment: .center, spacing: 12) {
            N64PadLeftColumn(held: held, stick: stick, setHeld: setHeld, setStick: setStick)
            Spacer(minLength: 8)
            N64HoldPadCapsule(title: "START", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
            Spacer(minLength: 8)
            N64PadRightColumn(held: held, setHeld: setHeld)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityLabel("N64 controls")
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
            PadShoulderButton(
                title: "L",
                isHeld: held.contains(.l),
                width: 64,
                fill: PadPalette.N64.shoulder,
                ink: PadPalette.N64.inkLight,
                onHeld: { setHeld(.l, $0) }
            )
            N64DPadView(held: held, arm: 40, setHeld: setHeld)
            N64StickPad(stick: stick, setStick: setStick, wellSize: 80)
            PadShoulderButton(
                title: "Z",
                isHeld: held.contains(.z),
                width: 72,
                fill: PadPalette.N64.z,
                ink: PadPalette.N64.inkLight,
                onHeld: { setHeld(.z, $0) }
            )
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
        VStack(spacing: 8) {
            PadShoulderButton(
                title: "R",
                isHeld: held.contains(.r),
                width: 64,
                fill: PadPalette.N64.shoulder,
                ink: PadPalette.N64.inkLight,
                onHeld: { setHeld(.r, $0) }
            )
            ZStack {
                N64HoldPadButton(
                    title: "B",
                    bit: .b,
                    isHeld: held.contains(.b),
                    diameter: 46,
                    fill: PadPalette.N64.b,
                    setHeld: setHeld
                )
                .offset(x: -20, y: 10)
                N64HoldPadButton(
                    title: "A",
                    bit: .a,
                    isHeld: held.contains(.a),
                    diameter: 54,
                    fill: PadPalette.N64.a,
                    setHeld: setHeld
                )
                .offset(x: 20, y: -10)
            }
            .frame(width: 110, height: 92)
            N64CCluster(held: held, diameter: 36, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 160, maxWidth: 200)
    }
}

import SwiftUI
import RetroPlayCore

/// Portrait-first NDS pad: DS Lite–like face, rectangular touch panel (not a GBA clone).
@available(iOS 18.0, *)
struct NDSFamilyPadView: View {
    enum Orientation {
        case portrait
        case landscape
    }

    let orientation: Orientation
    let held: NDSInput
    let setHeld: NDSHeldHandler
    /// Optional touch stub callback (bottom screen). Default no-op from host until wired.
    var onTouch: (@MainActor @Sendable (NDSTouch) -> Void)? = nil

    var body: some View {
        switch orientation {
        case .portrait:
            portraitPad
        case .landscape:
            landscapePad
        }
    }

    private var portraitPad: some View {
        PadChassis(fill: PadPalette.NDS.chassis, stroke: PadPalette.NDS.chassisStroke, cornerRadius: 22) {
            VStack(spacing: 8) {
                HStack {
                    PadShoulderButton(
                        title: "L",
                        isHeld: held.contains(.l),
                        width: 72,
                        fill: PadPalette.NDS.shoulder,
                        ink: PadPalette.NDS.ink,
                        onHeld: { setHeld(.l, $0) }
                    )
                    Spacer()
                    PadShoulderButton(
                        title: "R",
                        isHeld: held.contains(.r),
                        width: 72,
                        fill: PadPalette.NDS.shoulder,
                        ink: PadPalette.NDS.ink,
                        onHeld: { setHeld(.r, $0) }
                    )
                }

                HStack(alignment: .center, spacing: 8) {
                    VStack(spacing: 8) {
                        NDSDPadView(held: held, arm: 42, setHeld: setHeld)
                        HStack(spacing: 8) {
                            NDSHoldPadCapsule(
                                title: "SELECT",
                                bit: .select,
                                isHeld: held.contains(.select),
                                setHeld: setHeld
                            )
                            NDSHoldPadCapsule(
                                title: "START",
                                bit: .start,
                                isHeld: held.contains(.start),
                                setHeld: setHeld
                            )
                        }
                    }
                    Spacer(minLength: 4)
                    NDSFaceCluster(held: held, diameter: 40, setHeld: setHeld)
                }

                NDSTouchPanel(onTouch: onTouch)
            }
        }
        .accessibilityLabel("NDS controls")
    }

    private var landscapePad: some View {
        HStack(alignment: .center, spacing: 12) {
            NDSPadLeftColumn(held: held, setHeld: setHeld)
            Spacer(minLength: 8)
            NDSPadStartSelectRow(held: held, setHeld: setHeld)
            Spacer(minLength: 8)
            NDSPadRightColumn(held: held, setHeld: setHeld)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityLabel("NDS controls")
    }
}

/// Rectangular DS Touch Screen stand-in. Maps the view rect onto 256×192.
@available(iOS 18.0, *)
struct NDSTouchPanel: View {
    var onTouch: (@MainActor @Sendable (NDSTouch) -> Void)?
    @State private var pressed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PadPalette.NDS.touchBezel)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(PadPalette.NDS.touchGlass)
                    .padding(7)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(pressed ? 0.28 : 0.08), lineWidth: 1)
                    .padding(7)
                VStack(spacing: 2) {
                    Text("Touch Screen")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("256 × 192")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .opacity(0.7)
                }
                .foregroundStyle(Color.white.opacity(0.55))
                .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        pressed = true
                        let sample = PadHitTesting.ndsTouch(
                            x: Double(value.location.x),
                            y: Double(value.location.y),
                            width: Double(geo.size.width),
                            height: Double(geo.size.height)
                        )
                        onTouch?(NDSTouch(x: sample.x, y: sample.y, pressed: true))
                    }
                    .onEnded { _ in
                        pressed = false
                        onTouch?(.idle)
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .accessibilityLabel("Touch screen")
        .accessibilityAddTraits(.isButton)
    }
}

@available(iOS 18.0, *)
struct NDSPadLeftColumn: View {
    let held: NDSInput
    let setHeld: NDSHeldHandler

    var body: some View {
        VStack(spacing: 10) {
            PadShoulderButton(
                title: "L",
                isHeld: held.contains(.l),
                width: 64,
                fill: PadPalette.NDS.shoulder,
                ink: PadPalette.NDS.ink,
                onHeld: { setHeld(.l, $0) }
            )
            NDSDPadView(held: held, arm: 40, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 140, maxWidth: 160)
    }
}

@available(iOS 18.0, *)
struct NDSPadRightColumn: View {
    let held: NDSInput
    let setHeld: NDSHeldHandler

    var body: some View {
        VStack(spacing: 10) {
            PadShoulderButton(
                title: "R",
                isHeld: held.contains(.r),
                width: 64,
                fill: PadPalette.NDS.shoulder,
                ink: PadPalette.NDS.ink,
                onHeld: { setHeld(.r, $0) }
            )
            NDSFaceCluster(held: held, diameter: 36, setHeld: setHeld)
            Spacer(minLength: 0)
        }
        .frame(minWidth: 160, maxWidth: 190)
    }
}

@available(iOS 18.0, *)
struct NDSPadStartSelectRow: View {
    let held: NDSInput
    let setHeld: NDSHeldHandler

    var body: some View {
        HStack(spacing: 12) {
            NDSHoldPadCapsule(title: "SELECT", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            NDSHoldPadCapsule(title: "START", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

import SwiftUI
import RetroPlayCore

/// Portrait-first NDS pad. Dual-screen / touch are stubs until Play hosts a touch surface.
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
        VStack(spacing: 10) {
            HStack {
                NDSHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 44, setHeld: setHeld)
                Spacer()
                NDSHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 44, setHeld: setHeld)
            }
            .padding(.horizontal, 8)

            HStack(alignment: .center, spacing: 16) {
                NDSDPadView(held: held, arm: 44, setHeld: setHeld)
                Spacer(minLength: 4)
                NDSFaceCluster(held: held, diameter: 40, setHeld: setHeld)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 16) {
                NDSHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
                NDSHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
            }

            // Touch stub: tap zone stands in for bottom-screen stylus until dual-screen Play lands.
            touchStub
        }
        .padding(.vertical, 4)
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

    private var touchStub: some View {
        Text("Touch (stub)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.7)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Map local stub rect to ~NDS bottom screen (256×192).
                        let x = UInt16(min(255, max(0, Int(value.location.x))))
                        let y = UInt16(min(191, max(0, Int(value.location.y))))
                        onTouch?(NDSTouch(x: x, y: y, pressed: true))
                    }
                    .onEnded { _ in
                        onTouch?(.idle)
                    }
            )
            .accessibilityLabel("Touch screen stub")
    }
}

@available(iOS 18.0, *)
struct NDSPadLeftColumn: View {
    let held: NDSInput
    let setHeld: NDSHeldHandler

    var body: some View {
        VStack(spacing: 12) {
            NDSHoldPadButton(title: "L", bit: .l, isHeld: held.contains(.l), diameter: 42, setHeld: setHeld)
            NDSDPadView(held: held, arm: 42, setHeld: setHeld)
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
        VStack(spacing: 12) {
            NDSHoldPadButton(title: "R", bit: .r, isHeld: held.contains(.r), diameter: 42, setHeld: setHeld)
            NDSFaceCluster(held: held, diameter: 38, setHeld: setHeld)
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
        HStack(spacing: 16) {
            NDSHoldPadCapsule(title: "Select", bit: .select, isHeld: held.contains(.select), setHeld: setHeld)
            NDSHoldPadCapsule(title: "Start", bit: .start, isHeld: held.contains(.start), setHeld: setHeld)
        }
    }
}

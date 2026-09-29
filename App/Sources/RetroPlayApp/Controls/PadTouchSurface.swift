// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import RetroPlayCore

// MARK: - Regions reported by pad visuals

/// What a patch of the pad does when touched.
enum PadControlKind: Equatable, Sendable {
    /// One or more bits held while touched (several bits = a combo button).
    case button(UInt32)
    /// 8-way pad; the touch that lands on it keeps steering it even off the edge.
    case dpad(up: UInt32, down: UInt32, left: UInt32, right: UInt32)
    /// Analog stick; the touch that lands on it keeps steering it.
    case stick
    /// NDS bottom screen, mapped onto 256 × 192.
    case touchscreen
}

enum PadHitShape: Equatable, Sendable {
    case circle
    case rect
}

struct PadRegion: Equatable, Sendable {
    var id: String
    var kind: PadControlKind
    var frame: CGRect
    var shape: PadHitShape
}

struct PadRegionKey: PreferenceKey {
    static let defaultValue: [PadRegion] = []
    static func reduce(value: inout [PadRegion], nextValue: () -> [PadRegion]) {
        value.append(contentsOf: nextValue())
    }
}

enum PadSurface {
    /// Coordinate space shared by pad visuals and the touch surface overlay.
    static let space = "RetroPlay.PadSurface"
}

@available(iOS 18.0, *)
extension View {
    /// Report this view's frame as a touch region. Apply *after* press animations
    /// (scale) so the hit area does not move while a button is held.
    func padRegion(_ id: String, _ kind: PadControlKind, shape: PadHitShape = .rect) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PadRegionKey.self,
                    value: [PadRegion(
                        id: id,
                        kind: kind,
                        frame: proxy.frame(in: .named(PadSurface.space)),
                        shape: shape
                    )]
                )
            }
        }
    }
}

// MARK: - Touch surface

/// Transparent multi-touch layer over the whole Play screen. SwiftUI draws the pad;
/// this view owns every pad touch. That is what makes the controls feel like a pad:
///
/// * any number of fingers at once (D-pad + two face buttons + shoulder),
/// * slide a thumb between face buttons without lifting (rolling B → A),
/// * press the gap between two buttons to hold both,
/// * a D-pad / stick touch keeps steering after drifting off the graphic,
/// * a slightly-missed tap snaps to the nearest control,
/// * haptic tick on every new press.
///
/// Touches that start away from every control fall through to SwiftUI (menu button).
@available(iOS 18.0, *)
struct PadTouchSurface: UIViewRepresentable {
    var regions: [PadRegion]
    var hapticsEnabled: Bool
    /// `PadInputModel.releaseCount`; a change means the model dropped every touch.
    var releaseCount: Int
    var onChange: (PadTouchOutput) -> Void

    func makeUIView(context: Context) -> PadTouchView {
        let view = PadTouchView()
        view.releaseCount = releaseCount
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: PadTouchView, context: Context) {
        view.regions = regions
        view.hapticsEnabled = hapticsEnabled
        view.onChange = onChange
        if view.releaseCount != releaseCount {
            view.releaseCount = releaseCount
            view.resyncAfterRelease()
        }
    }
}

@available(iOS 18.0, *)
final class PadTouchView: UIView {
    var regions: [PadRegion] = [] {
        didSet {
            if regions != oldValue { reconcileTracks() }
        }
    }
    var hapticsEnabled = true
    var releaseCount = 0
    var onChange: ((PadTouchOutput) -> Void)?

    /// Extra reach around each control, in points.
    private let slop: CGFloat = 14
    /// Buttons are hit a little outside their drawn circle so neighbours overlap (combo zone).
    private let buttonReach: CGFloat = 1.12

    private enum Mode {
        case buttons(UInt32)
        case dpad(regionID: String, bits: UInt32)
        case stick(regionID: String, stick: TouchStick, x: Float, y: Float)
        case touchscreen(regionID: String, x: UInt16, y: UInt16)
    }

    private var tracks: [ObjectIdentifier: Mode] = [:]
    private var lastOutput = PadTouchOutput.idle
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    // Only claim touches that land on (or near) a control.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        nearestRegion(to: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.point(inside: point, with: event) ? self : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hapticsEnabled { haptics.prepare() }
        for touch in touches {
            let p = touch.location(in: self)
            guard let region = nearestRegion(to: p) else { continue }
            let key = ObjectIdentifier(touch)
            switch region.kind {
            case .button:
                tracks[key] = .buttons(buttonBits(at: p, fallback: region))
            case .dpad:
                tracks[key] = .dpad(regionID: region.id, bits: dpadBits(region, p))
            case .stick:
                // Zero where the thumb lands; deflection is measured from there.
                var stick = TouchStick(
                    originX: Double(p.x),
                    originY: Double(p.y),
                    radius: stickTravel(region)
                )
                let v = stick.update(x: Double(p.x), y: Double(p.y))
                tracks[key] = .stick(regionID: region.id, stick: stick, x: Float(v.x), y: Float(v.y))
            case .touchscreen:
                let t = touchscreenPoint(region, p)
                tracks[key] = .touchscreen(regionID: region.id, x: t.x, y: t.y)
            }
        }
        emit()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let mode = tracks[key] else { continue }
            let p = touch.location(in: self)
            switch mode {
            case .buttons(let old):
                // Slide between face buttons; keep the old press if the thumb wanders into a gap.
                let bits = buttonBits(at: p, fallback: nil)
                tracks[key] = .buttons(bits == 0 && isNearAnyButton(p) ? old : bits)
            case .dpad(let id, _):
                guard let region = regionWithID(id) else { continue }
                tracks[key] = .dpad(regionID: id, bits: dpadBits(region, p))
            case .stick(let id, var stick, _, _):
                let v = stick.update(x: Double(p.x), y: Double(p.y))
                tracks[key] = .stick(regionID: id, stick: stick, x: Float(v.x), y: Float(v.y))
            case .touchscreen(let id, _, _):
                guard let region = regionWithID(id) else { continue }
                let t = touchscreenPoint(region, p)
                tracks[key] = .touchscreen(regionID: id, x: t.x, y: t.y)
            }
        }
        emit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            tracks[ObjectIdentifier(touch)] = nil
        }
        emit()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            tracks.removeAll()
            emit()
        }
    }

    /// The input model was cleared (`releaseAll`) while fingers may still be down.
    /// Forget what was last sent so a held finger is sent again instead of being
    /// swallowed as "unchanged".
    func resyncAfterRelease() {
        lastOutput = .idle
        // Called during a SwiftUI update; publish on the next turn.
        DispatchQueue.main.async { [weak self] in self?.emit(haptic: false) }
    }

    // MARK: Geometry

    private func regionWithID(_ id: String) -> PadRegion? {
        regions.first { $0.id == id }
    }

    /// Drop tracks whose region disappeared (layout / rotation change).
    private func reconcileTracks() {
        var changed = false
        for (key, mode) in tracks {
            let id: String?
            switch mode {
            case .buttons: id = nil
            case .dpad(let r, _), .stick(let r, _, _, _), .touchscreen(let r, _, _): id = r
            }
            if let id, regionWithID(id) == nil {
                tracks[key] = nil
                changed = true
            }
        }
        // Regions change during a SwiftUI update; publish on the next turn.
        if changed {
            DispatchQueue.main.async { [weak self] in self?.emit() }
        }
    }

    private func distance(from p: CGPoint, to region: PadRegion) -> CGFloat {
        switch region.shape {
        case .circle:
            let r = min(region.frame.width, region.frame.height) / 2
            let d = hypot(p.x - region.frame.midX, p.y - region.frame.midY)
            return max(0, d - r)
        case .rect:
            let dx = max(region.frame.minX - p.x, 0, p.x - region.frame.maxX)
            let dy = max(region.frame.minY - p.y, 0, p.y - region.frame.maxY)
            return hypot(dx, dy)
        }
    }

    /// Region under the point, else the closest one within `slop`.
    private func nearestRegion(to p: CGPoint) -> PadRegion? {
        var best: PadRegion?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for region in regions {
            // Screen touch must be exact: a near-miss should not poke the game.
            let reach: CGFloat = region.kind == .touchscreen ? 0 : slop
            let d = distance(from: p, to: region)
            if d <= reach && d < bestDistance {
                best = region
                bestDistance = d
                if d == 0 && region.kind != .touchscreen { break }
            }
        }
        return best
    }

    private func isNearAnyButton(_ p: CGPoint) -> Bool {
        regions.contains { region in
            if case .button = region.kind { return distance(from: p, to: region) <= slop }
            return false
        }
    }

    /// Every button whose (slightly enlarged) area contains `p` — two at once in the gap.
    private func buttonBits(at p: CGPoint, fallback: PadRegion?) -> UInt32 {
        var bits: UInt32 = 0
        var nearest: (bits: UInt32, distance: CGFloat)?
        for region in regions {
            guard case .button(let b) = region.kind else { continue }
            let hit: Bool
            switch region.shape {
            case .circle:
                let r = min(region.frame.width, region.frame.height) / 2 * buttonReach
                hit = hypot(p.x - region.frame.midX, p.y - region.frame.midY) <= r
            case .rect:
                hit = region.frame.contains(p)
            }
            if hit {
                bits |= b
            } else {
                let d = distance(from: p, to: region)
                if d <= slop, d < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (b, d)
                }
            }
        }
        if bits != 0 { return bits }
        if let nearest { return nearest.bits }
        if let fallback, case .button(let b) = fallback.kind { return b }
        return 0
    }

    private func dpadBits(_ region: PadRegion, _ p: CGPoint) -> UInt32 {
        guard case .dpad(let up, let down, let left, let right) = region.kind else { return 0 }
        let dx = Double(p.x - region.frame.midX)
        let dy = Double(p.y - region.frame.midY)
        let size = Double(min(region.frame.width, region.frame.height))
        let dirs = PadHitTesting.dpad(dx: dx, dy: dy, deadzone: size * 0.12, diagonalRatio: 0.42)
        var bits: UInt32 = 0
        if dirs.up { bits |= up }
        if dirs.down { bits |= down }
        if dirs.left { bits |= left }
        if dirs.right { bits |= right }
        return bits
    }

    /// Thumb travel for full tilt: most of the well, and never less than ~a thumb width,
    /// so 20% tilt is a deliberate ~9 pt move rather than a twitch.
    private func stickTravel(_ region: PadRegion) -> Double {
        max(44, Double(min(region.frame.width, region.frame.height)) * 0.42)
    }

    private func touchscreenPoint(_ region: PadRegion, _ p: CGPoint) -> (x: UInt16, y: UInt16) {
        PadHitTesting.ndsTouch(
            x: Double(p.x - region.frame.minX),
            y: Double(p.y - region.frame.minY),
            width: Double(region.frame.width),
            height: Double(region.frame.height)
        )
    }

    // MARK: Output

    private func emit(haptic: Bool = true) {
        var out = PadTouchOutput.idle
        for mode in tracks.values {
            switch mode {
            case .buttons(let bits):
                out.buttons |= bits
            case .dpad(_, let bits):
                out.buttons |= bits
            case .stick(_, _, let x, let y):
                out.stickX = x
                out.stickY = y
            case .touchscreen(_, let x, let y):
                out.touchX = x
                out.touchY = y
                out.touching = true
            }
        }
        guard out != lastOutput else { return }
        let newlyPressed = out.buttons & ~lastOutput.buttons
        if haptic && hapticsEnabled && (newlyPressed != 0 || (out.touching && !lastOutput.touching)) {
            haptics.impactOccurred(intensity: 0.7)
        }
        lastOutput = out
        onChange?(out)
    }
}

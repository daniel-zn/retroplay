// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import QuartzCore
import IOSurface
import RetroPlayCore

/// Shows emulator frames. A display link pulls the newest frame from the core's
/// `VideoFrameStore` and puts it straight into a layer, so SwiftUI never
/// re-evaluates the Play screen per frame.
struct GameScreenView: UIViewRepresentable {
    let store: VideoFrameStore
    var smoothing: Bool
    /// DS in landscape: the frame's top and bottom halves (its two screens) side by side.
    var sideBySide = false
    /// The game is paused (pause menu open): no frames come, so the display link stops too.
    var paused = false

    func makeUIView(context: Context) -> GameScreenUIView {
        let view = GameScreenUIView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: GameScreenUIView, context: Context) {
        view.store = store
        view.smoothing = smoothing
        view.sideBySide = sideBySide
        view.paused = paused
    }
}

final class GameScreenUIView: UIView, DisplayLinkTarget {
    var store: VideoFrameStore? {
        didSet {
            if store !== oldValue {
                seen = 0
                layer.contents = nil
                oldValue?.removeDisplay(self)
                reportDisplaySize()
            }
        }
    }

    var smoothing = false {
        didSet {
            let filter: CALayerContentsFilter = smoothing ? .linear : .nearest
            for target in [layer, topHalf, bottomHalf] {
                target.magnificationFilter = filter
                target.minificationFilter = .linear
            }
        }
    }

    /// The frame split in two halves drawn left and right (DS screens in landscape).
    var sideBySide = false {
        didSet {
            guard sideBySide != oldValue else { return }
            topHalf.isHidden = !sideBySide
            bottomHalf.isHidden = !sideBySide
            let image = sideBySide ? layer.contents : topHalf.contents
            layer.contents = sideBySide ? nil : image
            topHalf.contents = sideBySide ? image : nil
            bottomHalf.contents = sideBySide ? image : nil
            setNeedsLayout()
        }
    }

    private let topHalf = CALayer()
    private let bottomHalf = CALayer()

    var paused = false {
        didSet { link?.isPaused = paused }
    }

    private var link: CADisplayLink?
    private var seen: UInt64 = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.isOpaque = true
        for (half, rect) in [(topHalf, CGRect(x: 0, y: 0, width: 1, height: 0.5)),
                             (bottomHalf, CGRect(x: 0, y: 0.5, width: 1, height: 0.5))] {
            half.contentsRect = rect
            half.contentsGravity = .resize
            half.magnificationFilter = .nearest
            half.isHidden = true
            half.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer.addSublayer(half)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let half = bounds.width / 2
        topHalf.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height)
        bottomHalf.frame = CGRect(x: half, y: 0, width: bounds.width - half, height: bounds.height)
        reportDisplaySize()
    }

    /// The picture's size in pixels on this screen, for cores that render at any resolution.
    private func reportDisplaySize() {
        guard let store else { return }
        guard window != nil else {
            store.removeDisplay(self)
            return
        }
        let scale = traitCollection.displayScale
        store.setDisplaySize(CGSize(width: bounds.width * scale, height: bounds.height * scale), for: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        reportDisplaySize()
        guard window != nil else { return }
        link = DisplayLinkProxy.link(for: self, fps: 30...60)
        link?.isPaused = paused
    }

    func refresh() {
        guard let store, let frame = store.latest(newerThan: seen) else { return }
        seen = frame.sequence
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if sideBySide {
            topHalf.contents = frame.contents
            bottomHalf.contents = frame.contents
        } else {
            layer.contents = frame.contents
        }
        CATransaction.commit()
    }
}

/// A view that pulls the newest frame on every display link tick.
@MainActor
protocol DisplayLinkTarget: AnyObject {
    func refresh()
}

/// Weak proxy: CADisplayLink retains its target.
private final class DisplayLinkProxy: NSObject {
    weak var target: (any DisplayLinkTarget)?

    @MainActor
    static func link(for target: any DisplayLinkTarget, fps: ClosedRange<Float>) -> CADisplayLink {
        let proxy = DisplayLinkProxy()
        proxy.target = target
        let link = CADisplayLink(target: proxy, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: fps.lowerBound, maximum: fps.upperBound,
                                                        preferred: fps.upperBound)
        link.add(to: .main, forMode: .common)
        return link
    }

    @objc func tick() {
        let target = self.target
        MainActor.assumeIsolated {
            target?.refresh()
        }
    }
}

/// A live layer behind a full-height landscape picture, so the bars beside it look black but
/// keep changing: Liquid Glass that hangs past the picture's edge is only refreshed when
/// what's under it changes, and over static black it trails the game. Each frame is shrunk
/// to 16 × 9 and drawn at 3% opacity (reads as black). 15 updates a second and a tiny
/// image, so it costs next to nothing.
struct AmbientScreenView: UIViewRepresentable {
    let store: VideoFrameStore
    var paused = false

    func makeUIView(context: Context) -> AmbientScreenUIView {
        let view = AmbientScreenUIView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: AmbientScreenUIView, context: Context) {
        view.store = store
        view.paused = paused
    }
}

final class AmbientScreenUIView: UIView, DisplayLinkTarget {
    var store: VideoFrameStore? {
        didSet {
            if store !== oldValue {
                seen = 0
                layer.contents = nil
            }
        }
    }

    var paused = false {
        didSet { link?.isPaused = paused }
    }

    private var link: CADisplayLink?
    private var seen: UInt64 = 0
    private let context = CGContext(
        data: nil, width: 16, height: 9, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        // Not 0: a fully transparent layer isn't drawn, and then nothing under the glass changes.
        alpha = 0.03
        layer.contentsGravity = .resizeAspectFill
        layer.magnificationFilter = .linear
        context?.interpolationQuality = .medium
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        link = DisplayLinkProxy.link(for: self, fps: 10...15)
        link?.isPaused = paused
    }

    func refresh() {
        guard let store, let context, let frame = store.latest(newerThan: seen) else { return }
        seen = frame.sequence
        if CFGetTypeID(frame.contents) == CGImage.typeID {
            context.draw(frame.contents as! CGImage, in: CGRect(x: 0, y: 0, width: 16, height: 9))
        } else if let surface = frame.contents as? IOSurface {
            // A GPU frame: the core reuses it soon, so sample it instead of keeping it.
            Self.sample(surface, into: context)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = context.makeImage()
        CATransaction.commit()
    }
}

extension AmbientScreenUIView {
    /// Nearest-neighbour 16 × 9 sample of a BGRA surface (144 reads; the picture is shown at 3%).
    fileprivate static func sample(_ surface: IOSurface, into context: CGContext) {
        guard let out = context.data else { return }
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let width = surface.width, height = surface.height, rowBytes = surface.bytesPerRow
        guard width > 0, height > 0 else { return }
        let src = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let dst = out.assumingMemoryBound(to: UInt8.self)
        let outRow = context.bytesPerRow
        for y in 0..<9 {
            let sy = (y * 2 + 1) * height / 18
            for x in 0..<16 {
                let sx = (x * 2 + 1) * width / 32
                let p = src + sy * rowBytes + sx * 4
                let q = dst + y * outRow + x * 4
                q[0] = p[2]; q[1] = p[1]; q[2] = p[0]; q[3] = 255  // BGRA → RGBX
            }
        }
    }
}

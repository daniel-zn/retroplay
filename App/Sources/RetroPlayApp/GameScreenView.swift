// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import QuartzCore
import RetroPlayCore

/// Shows emulator frames. A display link pulls the newest frame from the core's
/// `VideoFrameStore` and puts it straight into a layer, so SwiftUI never
/// re-evaluates the Play screen per frame.
@available(iOS 18.0, *)
struct GameScreenView: UIViewRepresentable {
    let store: VideoFrameStore
    var smoothing: Bool
    /// DS in landscape: the frame's top and bottom halves (its two screens) side by side.
    var sideBySide = false

    func makeUIView(context: Context) -> GameScreenUIView {
        let view = GameScreenUIView()
        view.store = store
        view.smoothing = smoothing
        view.sideBySide = sideBySide
        return view
    }

    func updateUIView(_ view: GameScreenUIView, context: Context) {
        view.store = store
        view.smoothing = smoothing
        view.sideBySide = sideBySide
    }
}

@available(iOS 18.0, *)
final class GameScreenUIView: UIView {
    var store: VideoFrameStore? {
        didSet {
            if store !== oldValue {
                seen = 0
                layer.contents = nil
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        // Weak proxy: CADisplayLink retains its target.
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func refresh() {
        guard let store, let frame = store.latest(newerThan: seen) else { return }
        seen = frame.sequence
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if sideBySide {
            topHalf.contents = frame.image
            bottomHalf.contents = frame.image
        } else {
            layer.contents = frame.image
        }
        CATransaction.commit()
    }
}

@available(iOS 18.0, *)
private final class DisplayLinkProxy: NSObject {
    weak var target: GameScreenUIView?

    init(_ target: GameScreenUIView) {
        self.target = target
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
@available(iOS 18.0, *)
struct AmbientScreenView: UIViewRepresentable {
    let store: VideoFrameStore

    func makeUIView(context: Context) -> AmbientScreenUIView {
        let view = AmbientScreenUIView()
        view.store = store
        return view
    }

    func updateUIView(_ view: AmbientScreenUIView, context: Context) {
        view.store = store
    }
}

@available(iOS 18.0, *)
final class AmbientScreenUIView: UIView {
    var store: VideoFrameStore? {
        didSet {
            if store !== oldValue {
                seen = 0
                layer.contents = nil
            }
        }
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
        let link = CADisplayLink(target: AmbientLinkProxy(self), selector: #selector(AmbientLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    fileprivate func refresh() {
        guard let store, let context, let frame = store.latest(newerThan: seen) else { return }
        seen = frame.sequence
        context.draw(frame.image, in: CGRect(x: 0, y: 0, width: 16, height: 9))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = context.makeImage()
        CATransaction.commit()
    }
}

@available(iOS 18.0, *)
private final class AmbientLinkProxy: NSObject {
    weak var target: AmbientScreenUIView?

    init(_ target: AmbientScreenUIView) {
        self.target = target
    }

    @objc func tick() {
        let target = self.target
        MainActor.assumeIsolated {
            target?.refresh()
        }
    }
}

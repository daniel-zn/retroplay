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

    func makeUIView(context: Context) -> GameScreenUIView {
        let view = GameScreenUIView()
        view.store = store
        view.smoothing = smoothing
        return view
    }

    func updateUIView(_ view: GameScreenUIView, context: Context) {
        view.store = store
        view.smoothing = smoothing
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
            layer.magnificationFilter = filter
            layer.minificationFilter = .linear
        }
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
        layer.contents = frame.image
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

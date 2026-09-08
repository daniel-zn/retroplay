import Foundation
import CoreGraphics

/// Receives frames from MGBACore on the run-loop queue; publishes on MainActor for SwiftUI.
public final class FrameSinkStore: EmulatorFrameSink, @unchecked Sendable {
    public private(set) var latestImage: CGImage?
    public var onFrame: ((CGImage) -> Void)?

    public init() {}

    public func coreDidProduceVideoFrame(_ frame: EmulatorVideoFrame) {
        guard let image = try? FrameBitmap.makeRGBAImage(from: frame) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.latestImage = image
            self?.onFrame?(image)
        }
    }

    public func coreDidProduceAudio(samples: UnsafePointer<Int16>, count: Int) {
        // Audio later
    }
}

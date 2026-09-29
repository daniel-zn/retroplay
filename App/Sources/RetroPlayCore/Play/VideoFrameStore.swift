// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics

/// Latest-frame mailbox between the emulation thread and the screen.
///
/// The emulation thread publishes as fast as it runs; the screen's display link
/// pulls at most one image per refresh. Old frames are simply replaced, so a slow
/// main thread can never build up a backlog (the old `DispatchQueue.main.async`
/// per frame did exactly that, and re-rendered the whole Play view each time).
public final class VideoFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var image: CGImage?
    private var sequence: UInt64 = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public init() {}

    /// Number of frames published so far (0 = nothing yet).
    public var frameCount: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }

    /// Emulation thread: snapshot `buffer` into an immutable image.
    public func publish(_ buffer: VideoFrameBuffer) {
        guard let bytes = buffer.bytes,
              let data = CFDataCreate(nil, bytes, buffer.byteCount),
              let provider = CGDataProvider(data: data),
              let made = CGImage(
                  width: buffer.width,
                  height: buffer.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: buffer.bytesPerRow,
                  space: colorSpace,
                  // Cores leave the 4th byte as 0 or garbage; never treat it as alpha.
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return }
        lock.lock()
        image = made
        sequence &+= 1
        lock.unlock()
    }

    /// Screen: the newest image if it is newer than `seen`.
    public func latest(newerThan seen: UInt64) -> (image: CGImage, sequence: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        guard sequence != seen, let image else { return nil }
        return (image, sequence)
    }

    /// Most recent image regardless of sequence (e.g. for a pause-menu thumbnail).
    public var currentImage: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return image
    }

    public func clear() {
        lock.lock()
        image = nil
        sequence = 0
        lock.unlock()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics
import IOSurface

/// Latest-frame mailbox between the emulation thread and the screen.
///
/// The emulation thread publishes as fast as it runs; the screen's display link
/// pulls at most one frame per refresh. Old frames are simply replaced, so a slow
/// main thread can never build up a backlog (the old `DispatchQueue.main.async`
/// per frame did exactly that, and re-rendered the whole Play view each time).
///
/// A frame is either a `CGImage` the core drew on the CPU, or an `IOSurface` a core rendered
/// on the GPU (PSP): both go straight into a layer's `contents`, so a GPU frame reaches the
/// screen, and an external display, without ever being copied by the CPU.
public final class VideoFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: AnyObject?
    private var sequence: UInt64 = 0
    private var displays: [ObjectIdentifier: CGSize] = [:]
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
        store(made)
    }

    /// Any thread: a frame the GPU finished drawing. The core must not draw into `surface`
    /// again while it is the newest frame (or still in use, `IOSurfaceIsInUse`).
    public func publish(surface: IOSurface) {
        store(surface)
    }

    private func store(_ object: AnyObject) {
        lock.lock()
        frame = object
        sequence &+= 1
        lock.unlock()
    }

    /// Screen: the newest frame if it is newer than `seen`, ready for `CALayer.contents`
    /// (a `CGImage` or an `IOSurface`).
    public func latest(newerThan seen: UInt64) -> (contents: AnyObject, sequence: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        guard sequence != seen, let frame else { return nil }
        return (frame, sequence)
    }

    public func clear() {
        lock.lock()
        frame = nil
        sequence = 0
        lock.unlock()
    }

    // MARK: - Where the picture is shown

    /// A screen showing these frames reports the picture's size in pixels, so a core that can
    /// render at any resolution (PSP) can match the largest one.
    public func setDisplaySize(_ size: CGSize, for owner: AnyObject) {
        lock.lock()
        if size.width > 0, size.height > 0 {
            displays[ObjectIdentifier(owner)] = size
        } else {
            displays[ObjectIdentifier(owner)] = nil
        }
        lock.unlock()
    }

    public func removeDisplay(_ owner: AnyObject) {
        lock.lock()
        displays[ObjectIdentifier(owner)] = nil
        lock.unlock()
    }

    /// The largest picture currently on a screen, in pixels (`.zero` if none).
    public var largestDisplaySize: CGSize {
        lock.lock()
        defer { lock.unlock() }
        return displays.values.reduce(.zero) { largest, size in
            size.width * size.height > largest.width * largest.height ? size : largest
        }
    }
}

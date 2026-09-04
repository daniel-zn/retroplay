import Foundation
import CoreGraphics

public enum FrameBitmapError: Error, Sendable {
    case invalidDimensions
    case unsupportedBytesPerPixel
}

/// Builds a `CGImage` from an `EmulatorVideoFrame` for SwiftUI/Metal previews.
public enum FrameBitmap {
    /// Interprets `frame.bytes` as 32-bit RGBA (8bpc).
    public static func makeRGBAImage(from frame: EmulatorVideoFrame) throws -> CGImage {
        guard frame.width > 0, frame.height > 0 else { throw FrameBitmapError.invalidDimensions }
        let bpp = 4
        guard frame.bytesPerRow >= frame.width * bpp else {
            throw FrameBitmapError.unsupportedBytesPerPixel
        }
        var data = frame.bytes
        return try data.withUnsafeMutableBytes { raw -> CGImage in
            guard let base = raw.baseAddress else { throw FrameBitmapError.invalidDimensions }
            let info = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: base,
                width: frame.width,
                height: frame.height,
                bitsPerComponent: 8,
                bytesPerRow: frame.bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info
            ), let image = context.makeImage() else {
                throw FrameBitmapError.invalidDimensions
            }
            return image
        }
    }
}

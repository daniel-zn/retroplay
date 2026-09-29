// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import Foundation
import ImageIO

/// Encodes extracted pixel buffers to PNG without touching the network.
enum CoverArtPNG {
    static func encodeRGBA(width: Int, height: Int, pixels: [UInt8]) -> Data? {
        guard width > 0, height > 0, pixels.count == width * height * 4 else { return nil }
        var pixels = pixels
        let bpp = 4
        return pixels.withUnsafeMutableBytes { raw -> Data? in
            guard let base = raw.baseAddress else { return nil }
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bpp,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let image = context.makeImage() else {
                return nil
            }
            return pngData(from: image)
        }
    }

    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How PPGe atlas glyphs are sampled by the software rasterizer.
///
/// `PPGeDrawCurrentText` emits UVs across the full atlas unless
/// `g_Config.bSoftwareRendering` is set. The software sampler then clamps any
/// texture larger than 512 to texel 511 (`ApplyTexelClampQuad`). The bundled
/// `ppge_atlas.zim` is 2048×2048, and the Ubuntu glyphs used for savedata labels
/// live outside that corner, so the clamp draws the wrong pixels.
///
/// With the flag set, PPGe shifts the texture address by 256-texel windows and
/// rewrites UVs into a 512×512 view. `textureScaleY` follows upstream and uses
/// the atlas width, which matches this square atlas.
public enum PPGeAtlasText: Sendable {
    public static let softwareTextureLimit = 512

    public struct Glyph: Equatable, Sendable {
        public var u: Float
        public var v: Float

        public init(u: Float, v: Float) {
            self.u = u
            self.v = v
        }

        public init(texelX: Int, texelY: Int, atlasWidth: Int, atlasHeight: Int) {
            self.u = Float(texelX) / Float(atlasWidth)
            self.v = Float(texelY) / Float(atlasHeight)
        }
    }

    public struct Sample: Equatable, Sendable {
        public var x: Float
        public var y: Float

        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
    }

    /// Texel a software draw of this glyph reads.
    ///
    /// `textureWindows` is `g_Config.bSoftwareRendering && atlas wider or taller than 512`.
    public static func sample(
        _ glyph: Glyph,
        atlasWidth: Int,
        atlasHeight: Int,
        textureWindows: Bool
    ) -> Sample {
        let width = Float(atlasWidth)
        let height = Float(atlasHeight)
        let needsWindows = atlasWidth > softwareTextureLimit || atlasHeight > softwareTextureLimit
        if textureWindows && needsWindows {
            let textureMaxPosX = width / 256
            let textureMaxPosY = height / 256
            let textureScaleX = width / Float(softwareTextureLimit)
            // Upstream uses atlas width for the Y scale, not atlas height.
            let textureScaleY = width / Float(softwareTextureLimit)
            let wantedPosX = floor(glyph.u * textureMaxPosX)
            let wantedPosY = floor(glyph.v * textureMaxPosY)
            let localU = (glyph.u - wantedPosX / textureMaxPosX) * textureScaleX
            let localV = (glyph.v - wantedPosY / textureMaxPosY) * textureScaleY
            return Sample(
                x: wantedPosX * 256 + localU * Float(softwareTextureLimit),
                y: wantedPosY * 256 + localV * Float(softwareTextureLimit)
            )
        }

        var x = glyph.u * width
        var y = glyph.v * height
        let clampEdge = Float(softwareTextureLimit - 1)
        if atlasWidth > softwareTextureLimit {
            x = min(max(x, 0), clampEdge)
        }
        if atlasHeight > softwareTextureLimit {
            y = min(max(y, 0), clampEdge)
        }
        return Sample(x: x, y: y)
    }
}

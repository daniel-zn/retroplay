// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// When and how a title glitches: now and then, for a moment, a few of its letters are drawn
/// "hacked" (sliced into three bands, one slid sideways, with lime and violet copies split off
/// around it) and the whole line smears sideways in lime and violet, then it's plain again
/// for several seconds. The look of the decode in the Mercurius apps, as an occasional flicker
/// on RetroPlay's titles only (body text never glitches). Pure timing, from a seed: the title's
/// text (so titles on screen together keep out of step) mixed with a fresh random number each
/// time it appears (so it never flickers the same way twice), and tests can check it; the app's
/// `GlitchTitleRenderer` draws what `frame(at:)` says over the text as laid out, so nothing
/// moves or reflows.
///
/// Light by design: a burst is five to seven frames of `cycle` (`frameCounts`), the first comes
/// `firstAfter` after the title appears, then one every `gaps`; between bursts the view sleeps
/// until the next one (`nextChange`). With Reduce Motion there are none.
public struct TitleGlitch: Sendable, Equatable {
    /// How long each frame of a burst shows (20 a second, as the decode's beat).
    public static let cycle = 0.05
    /// How many frames a burst has (each its own).
    public static let frameCounts = 5...7
    /// How long the longest burst lasts.
    public static var burst: Double { cycle * Double(frameCounts.upperBound) }
    /// The first burst, this long after the title appears: soon, so it's seen.
    public static let firstAfter = 0.6...2.5
    /// From one burst's start to the next: never so often that it's busy.
    public static let gaps = 4.0...12.0
    /// Variants of the hacked slicing (as the decode's: so a few hacked letters don't look stamped).
    public static let variants = 5

    /// How one glyph shows in a frame.
    public enum Shape: Sendable, Equatable {
        case plain
        /// Sliced and split into lime and violet, in one of `variants` slicings.
        case hacked(variant: Int)
        /// A solid block over the glyph (the burst's first frame, one glyph: the decode's pop-in).
        case block
    }

    /// A frame of a burst: each glyph's shape, and whether the line smears.
    public struct Frame: Sendable, Equatable {
        public let shapes: [Shape]
        public let smear: Bool
        /// Which frame of its burst (0 ..< its `frameCount`).
        public let index: Int
    }

    public let seed: UInt64
    /// A burst frame shown all the time (the screenshot tests' `-RetroPlayTitleGlitchFrame`); nil: as timed.
    public let frozen: Int?

    public init(seed: UInt64, frozen: Int? = nil) {
        self.seed = seed
        self.frozen = frozen.map { min(max($0, 0), Self.frameCounts.upperBound - 1) }
    }

    /// A seed from the title's text, so each title flickers on its own rhythm, mixed with
    /// `appearance` (the app's: a fresh random number each time the title appears), so it's
    /// never the same twice. A frozen frame ignores `appearance`, so screenshots are steady.
    public init(text: String, appearance: UInt64 = 0, frozen: Int? = nil) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        self.init(seed: frozen == nil ? hash ^ Self.mix(appearance) : hash, frozen: frozen)
    }

    /// How many frames burst `k` shows (`frameCounts`).
    public func frameCount(_ k: Int) -> Int {
        let n = UInt64(Self.frameCounts.count)
        return Self.frameCounts.lowerBound + Int(Self.mix(seed ^ (UInt64(k) &* 0xA24B_AED4_963E_E407)) % n)
    }

    /// When burst `k` starts, in seconds after the title appeared.
    public func burstStart(_ k: Int) -> Double {
        var t = Self.roll(seed, 0, in: Self.firstAfter)
        if k > 0 {
            for i in 1...k { t += Self.roll(seed, UInt64(i), in: Self.gaps) }
        }
        return t
    }

    /// The burst under way at `t` (seconds since the title appeared) and how far into it; nil: none.
    private func burst(at t: Double) -> (k: Int, into: Double)? {
        guard t >= 0 else { return nil }
        var k = 0
        var start = burstStart(0)
        while true {
            if t < start { return nil }
            if t < start + Self.cycle * Double(frameCount(k)) { return (k, t - start) }
            k += 1
            start += Self.roll(seed, UInt64(k), in: Self.gaps)
        }
    }

    /// What to draw at `t` for a title of `glyphs` glyphs; nil: the title as it is.
    public func frame(at t: Double, glyphs: Int, reduceMotion: Bool) -> Frame? {
        guard !reduceMotion, glyphs > 0 else { return nil }
        if let frozen { return frame(burst: 0, index: frozen, glyphs: glyphs) }
        guard let (k, into) = burst(at: t) else { return nil }
        return frame(burst: k, index: min(frameCount(k) - 1, Int(into / Self.cycle)), glyphs: glyphs)
    }

    /// Frame `index` of burst `k`: about a third of the glyphs hacked (at least one, at most
    /// half, so the title still reads), each in its own slicing; on the first frame one glyph
    /// is a block; the line smears on some frames, always on the first.
    func frame(burst k: Int, index: Int, glyphs: Int) -> Frame {
        let base = Self.mix(seed ^ (UInt64(k) &* 0x9E37_79B9) ^ (UInt64(index) &* 0x51ED_2701))
        var shapes = [Shape](repeating: .plain, count: glyphs)
        let most = max(1, glyphs / 2)
        var hacked = 0
        for i in 0..<glyphs where hacked < most {
            let roll = Self.mix(base &+ UInt64(i) &* 0x2545_F491)
            if roll % 3 == 0 {
                shapes[i] = .hacked(variant: Int((roll >> 8) % UInt64(Self.variants)))
                hacked += 1
            }
        }
        if hacked == 0 {
            let i = Int(base % UInt64(glyphs))
            shapes[i] = .hacked(variant: Int((base >> 8) % UInt64(Self.variants)))
        }
        if index == 0 {
            shapes[Int((base >> 16) % UInt64(glyphs))] = .block
        }
        let smear = index == 0 || (base >> 24) % 2 == 0
        return Frame(shapes: shapes, smear: smear, index: index)
    }

    /// When what `frame(at:)` shows next changes after `t`: the end of this frame in a burst,
    /// else the next burst's start. The view sleeps until then (nil: never, frozen or Reduce Motion).
    public func nextChange(after t: Double, reduceMotion: Bool) -> Double? {
        guard !reduceMotion, frozen == nil else { return nil }
        // Asked at a boundary (as a view that just woke for it is), the sums behind burst
        // starts can round either side of it: look just past it, so the answer is always later.
        let t = t + 1e-6
        if let (k, into) = burst(at: t) {
            let index = min(frameCount(k) - 1, Int(into / Self.cycle))
            return t - into + Double(index + 1) * Self.cycle
        }
        var k = 0
        while burstStart(k) <= t { k += 1 }
        return burstStart(k)
    }

    /// A number in `range` from the seed and `n`.
    static func roll(_ seed: UInt64, _ n: UInt64, in range: ClosedRange<Double>) -> Double {
        let unit = Double(mix(seed ^ (n &* 0xD1B5_4A32_D192_ED03)) % 10_001) / 10_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    /// splitmix64 (as the decode's): a well-spread number from a counter.
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

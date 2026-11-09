// SPDX-License-Identifier: GPL-3.0-or-later
import RetroPlayCore
import SwiftUI

extension View {
    /// The title glitch on the Text in this view: now and then, for a moment, a few letters drawn
    /// hacked in lime and violet and the line smeared (`TitleGlitch` says when). For titles only;
    /// body text stays plain. `text` seeds its rhythm, so each title flickers on its own. It
    /// draws over the text as laid out (nothing moves, VoiceOver reads the text as it is) and
    /// sleeps between bursts; with Reduce Motion it never glitches.
    @available(iOS 18.0, *)
    func retroPlayTitleGlitch(_ text: String) -> some View {
        modifier(TitleGlitchModifier(text: text))
    }
}

/// `-RetroPlayTitleGlitchFrame N` (a launch argument, read as a default): every title shows
/// frame N of a burst all the time, for the screenshot tests; `-1` turns the glitch off, so
/// other screenshots are steady.
enum TitleGlitchLaunch {
    static var frame: Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "RetroPlayTitleGlitchFrame") != nil else { return nil }
        return defaults.integer(forKey: "RetroPlayTitleGlitchFrame")
    }
}

@available(iOS 18.0, *)
private struct TitleGlitchModifier: ViewModifier {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Seconds since the title appeared, as of the last change.
    @State private var time = 0.0

    private var off: Bool { TitleGlitchLaunch.frame.map { $0 < 0 } ?? false }
    private var glitch: TitleGlitch { TitleGlitch(text: text, frozen: TitleGlitchLaunch.frame) }

    func body(content: Content) -> some View {
        content
            .textRenderer(GlitchTitleRenderer(glitch: glitch, time: time, reduceMotion: reduceMotion || off,
                                              dark: colorScheme == .dark))
            // A new title (Cover Flow's, as the covers move) starts its own rhythm.
            .task(id: "\(reduceMotion || off) \(text)") { await run(reduceMotion: reduceMotion || off) }
    }

    /// Wakes only when what shows changes (a frame of a burst, or the next burst's start).
    private func run(reduceMotion: Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        time = 0
        while !Task.isCancelled, let next = glitch.nextChange(after: time, reduceMotion: reduceMotion) {
            do { try await clock.sleep(until: start + .milliseconds(Int((next * 1000).rounded(.up)) + 1)) } catch { return }
            let elapsed = start.duration(to: clock.now)
            time = max(next + 0.0005, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
    }
}

/// Draws a title as `frame` says: its hacked glyphs in three bands with lime and violet copies
/// split off (as the Mercurius decode draws them), a block over one on a burst's first frame,
/// and the line smeared in lime and violet behind it.
@available(iOS 18.0, *)
private struct GlitchTitleRenderer: TextRenderer, Equatable {
    let glitch: TitleGlitch
    /// Seconds since the title appeared.
    let time: Double
    let reduceMotion: Bool
    let dark: Bool

    /// The fringes and smear reach a little past the text.
    var displayPadding: EdgeInsets { EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.reduce(0) { lines, line in lines + line.reduce(0) { $0 + $1.count } }
        guard let frame = glitch.frame(at: time, glyphs: glyphs, reduceMotion: reduceMotion) else {
            for line in layout { context.draw(line) }
            return
        }
        if frame.smear {
            for line in layout { Self.smear(line, dark: dark, in: &context) }
        }
        let solid: Color = dark ? .white : .black
        var g = 0
        for line in layout {
            for run in line {
                for slice in run {
                    defer { g += 1 }
                    let b = slice.typographicBounds
                    let h = b.ascent + b.descent
                    switch g < frame.shapes.count ? frame.shapes[g] : .plain {
                    case .plain:
                        context.draw(slice)
                    case .hacked(let variant):
                        Self.hacked(variant: variant, height: h, top: b.origin.y - b.ascent, dark: dark, in: context) { $0.draw(slice) }
                    case .block:
                        context.fill(Path(CGRect(x: b.rect.minX + 0.5, y: b.origin.y - b.ascent - h * 0.1,
                                                 width: max(h * 0.5, b.rect.width - 1), height: h * 1.2)),
                                     with: .color(solid))
                    }
                }
            }
        }
    }

    /// A glyph hacked: three bands, one slid sideways, lime and violet copies split off around it
    /// (the Mercurius decode's `hacked`, with its slicings and colours).
    static func hacked(variant: Int, height: CGFloat, top: CGFloat, dark: Bool, in context: GraphicsContext,
                       _ body: (inout GraphicsContext) -> Void) {
        let v = variant % 5
        let cuts = [0.0, [0.34, 0.42, 0.5, 0.3, 0.46][v], [0.66, 0.7, 0.62, 0.74, 0.8][v], 1.0]
        let slid = [1, 2, 0, 1, 2][v]
        let side: CGFloat = [1, -1, 1, -1, -1][v]
        let split: CGFloat = [1, 0.7, 1.25, 0.85, 1.1][v]
        let tilt: CGFloat = [0.35, -0.2, 0.15, 0.5, -0.4][v]
        let shift = max(1, height * 0.075)
        let lime = dark ? (0.72, 1.0, 0.25) : (0.3, 0.6, 0.0)
        let violet = dark ? (0.62, 0.42, 1.0) : (0.42, 0.2, 0.85)
        for band in 0..<3 {
            let bandTop = top + height * cuts[band], bottom = top + height * cuts[band + 1]
            let gap: CGFloat = band == 0 ? 0 : 0.5
            let dx = band == slid ? shift * 1.4 * side : 0
            for (tint, ox, oy) in [(Optional(lime), -shift * split + dx, -shift * tilt),
                                   (Optional(violet), shift * split + dx, shift * tilt), (nil, dx, 0)] {
                var layer = context
                layer.clip(to: Path(CGRect(x: -10_000, y: bandTop + gap, width: 20_000, height: bottom - bandTop - gap)))
                layer.translateBy(x: ox, y: oy)
                if let tint {
                    layer.opacity = 0.85
                    layer.addFilter(recolor(tint))
                }
                body(&layer)
            }
        }
    }

    /// The line smeared: lime and violet copies of it a little up and to the side (the decode's,
    /// scaled with the title's size: its offsets are for 17-point text).
    static func smear(_ line: Text.Layout.Line, dark: Bool, in context: inout GraphicsContext) {
        let bounds = line.typographicBounds
        let scale = max(1, (bounds.ascent + bounds.descent) / 20)
        let violet = dark ? (0.72, 0.62, 1.0) : (0.42, 0.3, 0.76), lime = dark ? (0.8, 0.96, 0.38) : (0.34, 0.52, 0.1)
        for (color, alpha, dx, dy) in [(violet, 0.55, 3.0, -2.0), (lime, 0.7, 1.5, -3.5)] {
            var layer = context
            layer.translateBy(x: dx * scale, y: dy * scale)
            layer.opacity = alpha
            layer.addFilter(recolor(color))
            layer.draw(line)
        }
    }

    /// Whatever is drawn, in one colour (its alpha kept).
    static func recolor(_ c: (Double, Double, Double)) -> GraphicsContext.Filter {
        var m = ColorMatrix()
        m.r1 = 0; m.g2 = 0; m.b3 = 0
        m.r5 = Float(c.0); m.g5 = Float(c.1); m.b5 = Float(c.2)
        return .colorMatrix(m)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// The titles' glitch is light and occasional: short bursts seconds apart, the first soon after
/// a title appears, a title that still reads during one, none at all with Reduce Motion, and a
/// view that sleeps between bursts without missing one.
final class TitleGlitchTests: XCTestCase {
    private let step = 0.01

    /// Every moment of the first `seconds` with its frame.
    private func frames(_ glitch: TitleGlitch, seconds: Double, glyphs: Int = 9, reduceMotion: Bool = false) -> [(Double, TitleGlitch.Frame?)] {
        stride(from: 0.0, to: seconds, by: step).map { ($0, glitch.frame(at: $0, glyphs: glyphs, reduceMotion: reduceMotion)) }
    }

    func testReduceMotionNeverGlitches() {
        for seed in [UInt64(1), 2, 99, 12345] {
            let glitch = TitleGlitch(seed: seed)
            XCTAssertTrue(frames(glitch, seconds: 60, reduceMotion: true).allSatisfy { $0.1 == nil }, "seed \(seed)")
            XCTAssertNil(glitch.nextChange(after: 0, reduceMotion: true))
            // A frozen glitch (the screenshot tests') honours it too.
            XCTAssertNil(TitleGlitch(seed: seed, frozen: 2).frame(at: 3, glyphs: 9, reduceMotion: true))
        }
    }

    func testBurstsAreShortOccasionalAndTheFirstComesSoon() {
        for seed in [UInt64(1), 7, 42, 2026, 0xFFFF_FFFF] {
            let glitch = TitleGlitch(seed: seed)
            let seen = frames(glitch, seconds: 120)
            // Runs of glitching moments: each one burst.
            var runs: [(start: Double, end: Double)] = []
            for (t, frame) in seen where frame != nil {
                if let last = runs.last, t - last.end <= step * 1.5 { runs[runs.count - 1].end = t } else { runs.append((t, t)) }
            }
            XCTAssertGreaterThanOrEqual(runs.count, 10, "seed \(seed): too few bursts in 2 minutes")
            XCTAssertLessThanOrEqual(runs.count, 25, "seed \(seed): too many bursts in 2 minutes")
            let first = try! XCTUnwrap(runs.first)
            XCTAssertTrue(first.start >= TitleGlitch.firstAfter.lowerBound - step && first.start <= TitleGlitch.firstAfter.upperBound + step,
                          "seed \(seed): first burst at \(first.start)")
            for run in runs {
                XCTAssertLessThanOrEqual(run.end - run.start, TitleGlitch.burst + step, "seed \(seed): a burst at \(run.start) runs long")
            }
            for (a, b) in zip(runs, runs.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.start - a.start, TitleGlitch.gaps.lowerBound - step * 1.5, "seed \(seed)")
                XCTAssertLessThanOrEqual(b.start - a.start, TitleGlitch.gaps.upperBound + step * 1.5, "seed \(seed)")
            }
            let share = Double(seen.filter { $0.1 != nil }.count) / Double(seen.count)
            XCTAssertLessThan(share, 0.07, "seed \(seed): glitching \(Int(share * 100))% of the time")
        }
    }

    func testABurstShowsEachOfItsFramesAndTheTitleStillReads() {
        let glitch = TitleGlitch(seed: 5)
        let start = glitch.burstStart(0)
        var indices: [Int] = []
        for f in 0..<TitleGlitch.frames {
            let frame = try! XCTUnwrap(glitch.frame(at: start + (Double(f) + 0.5) * TitleGlitch.cycle, glyphs: 9, reduceMotion: false))
            indices.append(frame.index)
        }
        XCTAssertEqual(indices, Array(0..<TitleGlitch.frames))

        for seed in UInt64(0)..<200 {
            for glyphs in [1, 2, 5, 9, 24] {
                for index in 0..<TitleGlitch.frames {
                    let frame = TitleGlitch(seed: seed).frame(burst: Int(seed % 3), index: index, glyphs: glyphs)
                    XCTAssertEqual(frame.shapes.count, glyphs)
                    let changed = frame.shapes.filter { $0 != .plain }.count
                    XCTAssertGreaterThanOrEqual(changed, 1, "seed \(seed) glyphs \(glyphs): nothing glitches")
                    XCTAssertLessThanOrEqual(changed, max(1, glyphs / 2) + (index == 0 ? 1 : 0), "seed \(seed) glyphs \(glyphs): too much to read")
                    let blocks = frame.shapes.filter { $0 == .block }.count
                    XCTAssertEqual(blocks, index == 0 ? 1 : 0, "seed \(seed): blocks only pop in on the first frame")
                    for case .hacked(let variant) in frame.shapes {
                        XCTAssertTrue((0..<TitleGlitch.variants).contains(variant))
                    }
                    if index == 0 { XCTAssertTrue(frame.smear, "the first frame smears") }
                }
            }
        }
    }

    func testTheSameTitleGlitchesTheSameWayAndTitlesDiffer() {
        XCTAssertEqual(TitleGlitch(text: "RetroPlay").burstStart(3), TitleGlitch(text: "RetroPlay").burstStart(3))
        XCTAssertEqual(TitleGlitch(text: "RetroPlay").frame(at: TitleGlitch(text: "RetroPlay").burstStart(0), glyphs: 9, reduceMotion: false),
                       TitleGlitch(text: "RetroPlay").frame(at: TitleGlitch(text: "RetroPlay").burstStart(0), glyphs: 9, reduceMotion: false))
        XCTAssertNotEqual(TitleGlitch(text: "RetroPlay").burstStart(0), TitleGlitch(text: "All Games").burstStart(0))
    }

    /// Sleeping until `nextChange` and drawing what `frame(at:)` says then shows every frame of
    /// every burst, and wakes only for them.
    func testSleepingUntilTheNextChangeMissesNoFrame() throws {
        for seed in [UInt64(3), 11, 777] {
            let glitch = TitleGlitch(seed: seed)
            var t = 0.0
            var wakes = 0
            var shown: [Int: Set<Int>] = [:]
            while t < 60 {
                let next = try XCTUnwrap(glitch.nextChange(after: t, reduceMotion: false))
                XCTAssertGreaterThan(next, t)
                t = next
                wakes += 1
                if let frame = glitch.frame(at: t + 1e-6, glyphs: 9, reduceMotion: false) {
                    var k = 0
                    while glitch.burstStart(k + 1) <= t { k += 1 }
                    shown[k, default: []].insert(frame.index)
                }
            }
            for (k, indices) in shown where glitch.burstStart(k) + TitleGlitch.burst < 60 {
                XCTAssertEqual(indices, Set(0..<TitleGlitch.frames), "seed \(seed): burst \(k) missed a frame")
            }
            XCTAssertLessThan(wakes, 120, "seed \(seed): woke \(wakes) times in a minute")
        }
    }

    func testAFrozenFrameShowsAllTheTime() {
        let glitch = TitleGlitch(seed: 9, frozen: 2)
        let frame = glitch.frame(at: 0, glyphs: 9, reduceMotion: false)
        XCTAssertEqual(frame?.index, 2)
        XCTAssertEqual(glitch.frame(at: 37.3, glyphs: 9, reduceMotion: false), frame)
        XCTAssertNil(glitch.nextChange(after: 0, reduceMotion: false), "a frozen title never needs waking")
        XCTAssertEqual(TitleGlitch(seed: 9, frozen: 99).frozen, TitleGlitch.frames - 1)
    }
}

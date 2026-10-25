// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class CoverFlowTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    // MARK: Focus after the list changes

    func testKeepsTheCentredGameWhileItIsListed() {
        // A new sort moves it; it stays in the middle.
        XCTAssertEqual(CoverFlow.focus(in: [c, a, b], current: a, currentIndex: 0, remembered: b), a)
    }

    func testDeletedGameIsReplacedByTheOneThatTookItsPlace() {
        XCTAssertEqual(CoverFlow.focus(in: [a, c, d], current: b, currentIndex: 1), c)
    }

    func testDeletingTheLastGameCentresTheNewLast() {
        XCTAssertEqual(CoverFlow.focus(in: [a, b], current: c, currentIndex: 2), b)
    }

    func testSwitchingFilterReturnsToTheGameLastCentredThere() {
        XCTAssertEqual(CoverFlow.focus(in: [a, b, c], current: d, remembered: c), c)
    }

    func testSwitchingBackToAFilterBeatsKeepingTheCentredGame() {
        // All (on c) → GBA (on b) → All: back to c, though All lists b too.
        XCTAssertEqual(CoverFlow.focus(in: [a, b, c], current: b, remembered: c), c)
    }

    func testFirstVisitToAFilterKeepsTheCentredGameWhenItHasIt() {
        // All → GBA while a GBA game is in the middle.
        XCTAssertEqual(CoverFlow.focus(in: [a, b, c], current: b, remembered: nil), b)
        XCTAssertEqual(CoverFlow.focus(in: [a, b, c], current: b, remembered: d), b)
    }

    func testFallsBackToTheFirstGame() {
        XCTAssertEqual(CoverFlow.focus(in: [a, b], current: d, remembered: c), a)
        XCTAssertEqual(CoverFlow.focus(in: [a, b], current: nil), a)
    }

    func testEmptyListHasNoFocus() {
        XCTAssertNil(CoverFlow.focus(in: [], current: a, currentIndex: 0, remembered: a))
    }

    // MARK: Remembered position

    func testMemoryRoundTrips() {
        var memory = CoverFlow.Memory(raw: "")
        memory["all"] = a
        memory["gba"] = b
        let restored = CoverFlow.Memory(raw: memory.raw)
        XCTAssertEqual(restored, memory)
        XCTAssertEqual(restored["all"], a)
        XCTAssertEqual(restored["gba"], b)
        XCTAssertNil(restored["n64"])
    }

    func testMemoryOverwritesAndClears() {
        var memory = CoverFlow.Memory(raw: "all=\(a.uuidString)")
        memory["all"] = c
        XCTAssertEqual(CoverFlow.Memory(raw: memory.raw)["all"], c)
        memory["all"] = nil
        XCTAssertEqual(memory.raw, "")
    }

    func testMemorySkipsDamagedEntries() {
        let memory = CoverFlow.Memory(raw: "all=nonsense;;gba;nds=\(d.uuidString)")
        XCTAssertEqual(memory.games, ["nds": d])
    }

    // MARK: Geometry

    func testCoverFitsTheSmallerOfHeightAndWidth() {
        // Landscape: the height does.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 180).coverWidth, 180)
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 180).coverHeight, 180)
        // Never below the minimum, even with large text squeezing the space.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 40).coverWidth, 110)
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 40).coverHeight, 110)
    }

    func testPortraitCoverFillsMostOfTheScreen() {
        // iPhone 17 Pro Max portrait: 440 wide, ~560 left for the covers.
        let metrics = CoverFlow.Metrics.fitting(width: 440, height: 560)
        XCTAssertGreaterThanOrEqual(metrics.coverWidth, 440 * 0.78)
        // The old fit (56% of the width, square) left most of the height empty.
        XCTAssertGreaterThan(metrics.coverWidth, 440 * 0.56 * 1.25)
        // Upright boxes get a taller slot, within the height.
        XCTAssertGreaterThan(metrics.coverHeight, metrics.coverWidth * 1.3)
        XCTAssertLessThanOrEqual(metrics.coverHeight, 560)
        // A smaller phone, and a short space (large text): the slot never outgrows it.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 375, height: 500).coverWidth, 300)
        let squeezed = CoverFlow.Metrics.fitting(width: 402, height: 240)
        XCTAssertEqual(squeezed.coverWidth, 240)
        XCTAssertEqual(squeezed.coverHeight, 240)
    }

    func testSideCoversStack() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        XCTAssertLessThan(metrics.stackSpacing, metrics.coverWidth / 5)
        XCTAssertGreaterThan(metrics.stackSpacing, metrics.coverWidth / 10)
    }

    func testFirstSideCoverStandsCloseToTheMiddle() {
        // Half a cover out: the side cover tucks in behind the middle one's edge.
        let metrics = CoverFlow.Metrics(coverSide: 300)
        XCTAssertEqual(metrics.firstGap, 150)
        XCTAssertEqual(metrics.step + metrics.pose(distance: metrics.step).xShift, metrics.firstGap)
        // Was 64% of a cover; the stack behind keeps its spacing.
        XCTAssertLessThan(metrics.firstGap, 300 * 0.64)
        let second = metrics.step * 2 + metrics.pose(distance: metrics.step * 2).xShift
        XCTAssertEqual(second - metrics.firstGap, metrics.stackSpacing)
    }

    func testOneGameIsAFullDragAway() {
        // The finger drags about as far per game as the middle cover moves to the side, so
        // the row tracks it calmly instead of racing through the tightly packed stack.
        let metrics = CoverFlow.Metrics(coverSide: 300)
        XCTAssertGreaterThan(metrics.step, metrics.stackSpacing * 2.5)
        XCTAssertGreaterThanOrEqual(metrics.step, 120)
    }

    func testLayoutDistanceInvertsTheDrawnPosition() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for distance in [0.0, 30, metrics.step, metrics.step * 2.5, metrics.step * 9] {
            let drawn = distance + metrics.pose(distance: distance).xShift
            // The easing is flat at the middle and side spots, so its inverse is only
            // float-exact to a few millionths of a point there.
            XCTAssertEqual(metrics.layoutDistance(forVisual: drawn), distance, accuracy: 1e-4)
        }
    }

    // MARK: Swipes

    private let swipe = CoverFlow.Metrics(coverSide: 300)

    /// Where a swipe that started centred on `from` and was let go at `release` (in covers)
    /// comes to rest.
    private func rest(from: Double = 10, _ release: Double, _ velocity: Double, count: Int = 50) -> Int {
        swipe.restingIndex(start: from * swipe.step, release: release * swipe.step, velocity: velocity, count: count)
    }

    func testSlowReleaseSettlesOnTheNearestCover() {
        XCTAssertEqual(rest(10.3, 0), 10)
        XCTAssertEqual(rest(10.6, 120), 11)
        XCTAssertEqual(rest(10.6, -120), 11)
        // A slow drag across several covers stays where it was let go.
        XCTAssertEqual(rest(16.2, 100), 16)
    }

    func testNudgeMovesOneGame() {
        // A light push (below a flick) moves to the next game, either way.
        XCTAssertEqual(rest(10.3, 500), 11)
        XCTAssertEqual(rest(10.2, 650), 11)
        XCTAssertEqual(rest(9.7, -500), 9)
    }

    func testGentleFlicksCarryAFewGames() {
        XCTAssertEqual(rest(10.3, 900), 12)
        XCTAssertEqual(rest(10.3, 1100), 13)
        XCTAssertEqual(rest(9.7, -900), 8)
    }

    func testFasterFlicksTravelFurther() {
        // Momentum: the faster the flick, the further it goes.
        XCTAssertEqual(rest(10.3, 2000), 15)
        XCTAssertEqual(rest(10.3, 3000), 18)
        XCTAssertEqual(rest(10.3, 5000), 23)
        XCTAssertLessThan(rest(10.3, 2000), rest(10.3, 5000))
        // However hard: never past the limit.
        XCTAssertEqual(rest(from: 40, 40.3, 60_000, count: 100), 40 + CoverFlow.maxSwipeTravel)
        XCTAssertEqual(rest(from: 40, 39.7, -60_000, count: 100), 40 - CoverFlow.maxSwipeTravel)
    }

    func testFastLongDragKeepsWhatTheFingerCovered() {
        // A quick drag across five covers, then a flick: at least as far as the finger went.
        XCTAssertGreaterThanOrEqual(rest(15.1, 2000), 15)
    }

    func testFlickAgainstTheDragGoesBackwards() {
        // Nudged right, then flicked left: back past where it started.
        XCTAssertLessThan(rest(10.4, -900), 10)
    }

    func testSwipeStartingMidRowCountsFromTheNearestCover() {
        // Caught while still moving (between 7 and 8): a swipe counts from 8.
        XCTAssertEqual(rest(from: 7.6, 8.1, 500), 9)
    }

    func testSwipesStopAtTheEnds() {
        XCTAssertEqual(rest(from: 0, 0.2, -5000, count: 5), 0)
        XCTAssertEqual(rest(from: 4, 3.8, 5000, count: 5), 4)
        XCTAssertEqual(rest(from: 0, 0, 900, count: 1), 0)
        XCTAssertEqual(swipe.restingIndex(start: 0, release: 0, velocity: 900, count: 0), 0)
    }

    func testLandscapeCoversStillNeedAFullDragPerGame() {
        // Small (height-limited) covers: a game is still at least 120 points of drag.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 874, height: 190).step, 120)
    }

    func testMiddleCoverFacesFront() {
        let pose = CoverFlow.Metrics(coverSide: 200).pose(distance: 0)
        XCTAssertEqual(pose.rotation, 0)
        XCTAssertEqual(pose.scale, 1)
        XCTAssertEqual(pose.xShift, 0)
        XCTAssertEqual(pose.dimming, 0)
    }

    func testSidesAreMirrored() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for distance in [10.0, 48, 100, 500] {
            let left = metrics.pose(distance: -distance), right = metrics.pose(distance: distance)
            XCTAssertEqual(left.rotation, -right.rotation, accuracy: 1e-9)
            XCTAssertEqual(left.xShift, -right.xShift, accuracy: 1e-9)
            XCTAssertEqual(left.scale, right.scale, accuracy: 1e-9)
        }
    }

    func testCoversPastTheFirstKeepTheirAngleAndGap() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        let first = metrics.pose(distance: metrics.step)
        let third = metrics.pose(distance: metrics.step * 3)
        XCTAssertEqual(abs(first.rotation), CoverFlow.sideAngle)
        XCTAssertEqual(third.rotation, first.rotation)
        // The first side cover stands `firstGap` from the middle, the third two stack
        // spacings further.
        XCTAssertEqual(metrics.step + first.xShift, metrics.firstGap)
        XCTAssertEqual(metrics.step * 3 + third.xShift, metrics.firstGap + 2 * metrics.stackSpacing)
    }

    func testTurningIsContinuousThroughTheMiddle() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        XCTAssertLessThan(abs(metrics.pose(distance: 1).rotation), 3)
        var last = 0.0
        for i in 1...100 {
            let turn = abs(metrics.pose(distance: metrics.step * Double(i) / 100).rotation)
            XCTAssertGreaterThanOrEqual(turn, last)
            last = turn
        }
    }

    func testTurnLeadsTheSlide() {
        // Leaving the middle a cover turns ahead of its slide; arriving it stays turned
        // until late.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        func turn(_ fraction: Double) -> Double { abs(metrics.pose(distance: metrics.step * fraction).rotation) }
        func slid(_ fraction: Double) -> Double {
            let distance = metrics.step * fraction
            return (distance + metrics.pose(distance: distance).xShift) / metrics.firstGap
        }
        for i in 1...9 {
            let fraction = Double(i) / 10
            XCTAssertGreaterThanOrEqual(turn(fraction) / CoverFlow.sideAngle, slid(fraction), "at \(fraction)")
        }
        XCTAssertGreaterThan(turn(0.5), CoverFlow.sideAngle * 0.9)
        XCTAssertGreaterThan(turn(0.75), CoverFlow.sideAngle * 0.99)
    }

    func testMiddleCoverLingers() {
        // A tenth of the way to the next game the middle cover has hardly moved or turned;
        // the move happens in the middle of the swipe.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for fraction in [0.1, -0.1] {
            let distance = metrics.step * fraction
            let pose = metrics.pose(distance: distance)
            XCTAssertLessThan(abs(distance + pose.xShift), metrics.firstGap * 0.04)
            XCTAssertLessThan(abs(pose.rotation), 8)
            XCTAssertGreaterThan(pose.scale, 0.97)
        }
        // The arriving cover settles the same way: a tenth out it's nearly in place.
        let arriving = metrics.step * 0.9
        XCTAssertGreaterThan(arriving + metrics.pose(distance: arriving).xShift, metrics.firstGap * 0.96)
        // Halfway, each is halfway.
        let half = metrics.step / 2
        XCTAssertEqual(half + metrics.pose(distance: half).xShift, metrics.firstGap / 2, accuracy: 1e-9)
    }

    func testPassingCoversKeepTheirSpacing() {
        // Eased both ways alike, the leaving and arriving covers stay `firstGap` apart.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for i in 0...20 {
            let fraction = Double(i) / 20
            let leaving = metrics.step * fraction, arriving = -metrics.step * (1 - fraction)
            let apart = (leaving + metrics.pose(distance: leaving).xShift)
                - (arriving + metrics.pose(distance: arriving).xShift)
            XCTAssertEqual(apart, metrics.firstGap, accuracy: 1e-9)
        }
    }

    func testPassingCoversDoNotOverlap() {
        // The two covers either side of the middle mid-swipe (where they swap which is in
        // front) stay apart, for the widest cover the slot holds, in portrait and landscape.
        // Perspective is left out: it only narrows the inner edge further.
        for metrics in [CoverFlow.Metrics.fitting(width: 402, height: 560),
                        CoverFlow.Metrics.fitting(width: 874, height: 280),
                        CoverFlow.Metrics(coverSide: 200)] {
            for i in 0...20 {
                let fraction = 0.4 + Double(i) / 100
                func innerEdge(_ distance: Double) -> Double {
                    let pose = metrics.pose(distance: distance)
                    let centre = abs(distance + pose.xShift)
                    let half = metrics.coverWidth / 2 * pose.scale * cos(pose.rotation * .pi / 180)
                    return centre - half
                }
                let gap = innerEdge(metrics.step * fraction) + innerEdge(-metrics.step * (1 - fraction))
                XCTAssertGreaterThanOrEqual(gap, 0, "overlap at \(fraction) for \(metrics.coverWidth)")
            }
        }
    }

    func testIndexForOffsetRoundsAndClamps() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        XCTAssertEqual(metrics.index(forOffset: 0, count: 10), 0)
        XCTAssertEqual(metrics.index(forOffset: metrics.step * 2.4, count: 10), 2)
        XCTAssertEqual(metrics.index(forOffset: metrics.step * 2.6, count: 10), 3)
        XCTAssertEqual(metrics.index(forOffset: -50, count: 10), 0)
        XCTAssertEqual(metrics.index(forOffset: metrics.step * 40, count: 10), 9)
        XCTAssertEqual(metrics.index(forOffset: 100, count: 0), 0)
    }
}

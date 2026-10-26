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

    func testAllSideCoversFaceLeft() {
        // Like a fanned deck: covers on both sides turn the same way, mirrored only in where
        // they stand.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for fraction in [0.25, 0.5, 1, 3] {
            let right = metrics.pose(distance: metrics.step * fraction)
            let left = metrics.pose(distance: -metrics.step * fraction)
            XCTAssertLessThan(right.rotation, 0)
            XCTAssertEqual(left.rotation, right.rotation, accuracy: 1e-9)
            XCTAssertEqual(left.scale, right.scale, accuracy: 1e-9)
        }
    }

    func testCoversPastTheFirstKeepTheirAngleAndGap() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        func drawn(_ fraction: Double) -> Double {
            let distance = metrics.step * fraction
            return distance + metrics.pose(distance: distance).xShift
        }
        XCTAssertEqual(abs(metrics.pose(distance: metrics.step).rotation), CoverFlow.sideAngle)
        XCTAssertEqual(metrics.pose(distance: -metrics.step * 3).rotation, -CoverFlow.sideAngle)
        // The first side covers stand at their gaps, the third two stack spacings further.
        XCTAssertEqual(drawn(1), metrics.firstGap)
        XCTAssertEqual(drawn(3), metrics.firstGap + 2 * metrics.stackSpacing)
        XCTAssertEqual(drawn(-1), -metrics.leftGap)
        XCTAssertEqual(drawn(-3), -(metrics.leftGap + 2 * metrics.stackSpacing))
    }

    func testCoversSlideInStepWithTheFinger() {
        // No pause in the middle: between the middle and the first side spot a cover moves
        // evenly with the drag.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for i in 1...9 {
            let fraction = Double(i) / 10
            let right = metrics.step * fraction, left = -right
            XCTAssertEqual(right + metrics.pose(distance: right).xShift, metrics.firstGap * fraction, accuracy: 1e-9)
            XCTAssertEqual(left + metrics.pose(distance: left).xShift, -metrics.leftGap * fraction, accuracy: 1e-9)
        }
    }

    func testTurnEasesInAndOut() {
        // The turn starts and ends gently (no snap as a cover leaves the middle or settles
        // into a stack) and only ever grows away from the middle.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        func turn(_ fraction: Double) -> Double { abs(metrics.pose(distance: metrics.step * fraction).rotation) }
        XCTAssertLessThan(turn(0.1), CoverFlow.sideAngle * 0.05)
        XCTAssertEqual(turn(0.5), CoverFlow.sideAngle / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(turn(0.9), CoverFlow.sideAngle * 0.95)
        XCTAssertLessThan(abs(metrics.pose(distance: 1).rotation), 0.1)
        var last = 0.0
        for i in 1...100 {
            let now = turn(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(now, last)
            last = now
        }
    }

    func testLeftStackNeverCoversTheMiddleCover() {
        // Facing left, a left cover's inner edge comes forward, and the left stack lies on top:
        // the first one stands far enough out that even the widest cover (drawn in a stronger
        // perspective than the view's, to be safe) clears the middle cover's edge.
        for metrics in [CoverFlow.Metrics.fitting(width: 402, height: 560),
                        CoverFlow.Metrics.fitting(width: 874, height: 280),
                        CoverFlow.Metrics(coverSide: 200)] {
            let pose = metrics.pose(distance: -metrics.step)
            let half = metrics.coverWidth / 2 * pose.scale
            let angle = abs(pose.rotation) * .pi / 180
            let eye = metrics.coverWidth / CoverFlow.perspective
            let forward = half * cos(angle) / (1 - half * sin(angle) / eye)
            let innerEdge = -metrics.step + pose.xShift + forward
            XCTAssertLessThanOrEqual(innerEdge, -metrics.coverWidth / 2, "for \(metrics.coverWidth)")
            // And not much further: the stack still reads as one row with the middle.
            XCTAssertLessThan(metrics.leftGap, metrics.coverWidth * 0.85)
        }
    }

    func testCoversKeepOneDrawingOrder() {
        // Earlier games on top, always: no two covers swap places mid-swipe.
        XCTAssertGreaterThan(CoverFlow.layer(index: 0), CoverFlow.layer(index: 1))
        XCTAssertGreaterThan(CoverFlow.layer(index: 9), CoverFlow.layer(index: 10))
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

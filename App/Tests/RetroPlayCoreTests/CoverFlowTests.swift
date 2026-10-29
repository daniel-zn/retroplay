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

    func testEveryCoverSharesOneWidth() {
        // Wide, square and tall boxes in one row: all drawn the same width, each as tall as
        // its own shape (never stretched).
        let metrics = CoverFlow.Metrics.fitting(width: 402, height: 560, tallestAspect: 0.58)
        for aspect in [0.58, 0.71, 1.0, 1.1, 1.37, 1.4] {
            let size = metrics.coverSize(aspect: aspect)
            XCTAssertEqual(size.width, metrics.coverWidth, "for \(aspect)")
            XCTAssertEqual(size.width / size.height, aspect, accuracy: 1e-9, "for \(aspect)")
            XCTAssertLessThanOrEqual(size.height, metrics.coverHeight + 0.5)
        }
        // Box art taller than the row made room for is fitted to the height (narrower) rather
        // than running over it.
        let taller = metrics.coverSize(aspect: 0.5)
        XCTAssertEqual(taller.height, metrics.coverHeight)
        XCTAssertLessThan(taller.width, metrics.coverWidth)
    }

    func testTheTallestCoverSetsTheWidth() {
        // Landscape: the height limits it, so the tallest shape in the list decides the width.
        let upright = CoverFlow.Metrics.fitting(width: 874, height: 280, tallestAspect: 0.71)
        XCTAssertEqual(upright.coverWidth, (280 * 0.71).rounded(.down))
        XCTAssertLessThanOrEqual(upright.coverHeight, 280)
        let psp = CoverFlow.Metrics.fitting(width: 874, height: 280, tallestAspect: 0.58)
        XCTAssertLessThan(psp.coverWidth, upright.coverWidth)
        XCTAssertLessThanOrEqual(psp.coverHeight, 280)
        // Only wide covers in the list: they grow as wide as the stacks leave room for.
        let wide = CoverFlow.Metrics.fitting(width: 874, height: 280, tallestAspect: 1.37)
        XCTAssertEqual(wide.coverWidth, 383)
        // Never below the minimum, even with large text squeezing the space.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 40).coverWidth, 110)
    }

    func testPortraitCoverFillsMostOfTheScreen() {
        // iPhone 17 Pro Max portrait: 440 wide, ~560 left for the covers.
        let metrics = CoverFlow.Metrics.fitting(width: 440, height: 560, tallestAspect: 0.71)
        // 60% of the width (it was 80%, then 68%), leaving the stacks room either side.
        XCTAssertEqual(metrics.coverWidth, (440 * 0.6).rounded(.down))
        XCTAssertLessThan(metrics.coverWidth, 440 * 0.62)
        // The old fit (56% of the width, square) left most of the height empty.
        // The tallest boxes stand within the height.
        XCTAssertLessThanOrEqual(metrics.coverHeight, 560)
        // A smaller phone, and a short space (large text): the slot never outgrows it.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 375, height: 500).coverWidth, 225)
        let squeezed = CoverFlow.Metrics.fitting(width: 402, height: 240)
        XCTAssertEqual(squeezed.coverWidth, (240 * 0.71).rounded(.down))
        XCTAssertLessThanOrEqual(squeezed.coverHeight, 240)
    }

    func testSideCoversStack() {
        // Spread out along the flanks (they were 11% of a cover apart), still overlapping.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        XCTAssertLessThan(metrics.stackSpacing, metrics.coverWidth / 5)
        XCTAssertGreaterThanOrEqual(metrics.stackSpacing, metrics.coverWidth * 0.16)
    }

    func testSideCoversTurnPartWayToShowTheirFronts() {
        // Turned less than edge-on (they were 70°), so the stacks fill the flanks.
        XCTAssertLessThanOrEqual(CoverFlow.sideAngle, 56)
        XCTAssertGreaterThanOrEqual(CoverFlow.sideAngle, 45)
    }

    func testFirstSideCoverStandsCloseToTheMiddle() {
        // Under half a cover out: the right cover tucks in behind the middle one's edge.
        let metrics = CoverFlow.Metrics(coverSide: 300)
        XCTAssertEqual(metrics.firstGap, 135)
        XCTAssertEqual(-metrics.step + metrics.pose(distance: -metrics.step).xShift, -metrics.firstGap)
        // Was 64% of a cover, then 50%; the stack behind keeps its spacing.
        XCTAssertLessThan(metrics.firstGap, 300 * 0.5)
        let second = -metrics.step * 2 + metrics.pose(distance: -metrics.step * 2).xShift
        XCTAssertEqual(-second - metrics.firstGap, metrics.stackSpacing)
    }

    func testOneGameIsAFullDragAway() {
        // The finger drags about as far per game as the middle cover moves to the side, so
        // the row tracks it calmly instead of racing through the tightly packed stack.
        let metrics = CoverFlow.Metrics(coverSide: 300)
        XCTAssertGreaterThan(metrics.step, metrics.stackSpacing * 2)
        XCTAssertGreaterThanOrEqual(metrics.step, 120)
    }

    func testLayoutDistanceInvertsTheDrawnPosition() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        // On the left, the closer-packed side (its first cover tucks under the middle one), so
        // laying out that far covers the right too.
        for distance in [0.0, 30, metrics.step, metrics.step * 2.5, metrics.step * 9] {
            let drawn = -distance + metrics.pose(distance: -distance).xShift
            XCTAssertEqual(metrics.layoutDistance(forVisual: drawn), distance, accuracy: 1e-4)
        }
        // The right stands further out for the same layout distance.
        let right = metrics.step + metrics.pose(distance: metrics.step).xShift
        XCTAssertGreaterThan(right, metrics.firstGap)
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
        XCTAssertEqual(pose.xShift, 0)
        XCTAssertEqual(pose.dimming, 0)
    }

    func testAllSideCoversFaceRight() {
        // Like a fanned deck: covers on both sides turn the same way, mirrored only in where
        // they stand.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for fraction in [0.25, 0.5, 1, 3] {
            let right = metrics.pose(distance: metrics.step * fraction)
            let left = metrics.pose(distance: -metrics.step * fraction)
            XCTAssertGreaterThan(right.rotation, 0)
            XCTAssertEqual(left.rotation, right.rotation, accuracy: 1e-9)
        }
    }

    func testCoversPastTheFirstKeepTheirAngleAndGap() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        func drawn(_ fraction: Double) -> Double {
            let distance = metrics.step * fraction
            return distance + metrics.pose(distance: distance).xShift
        }
        XCTAssertEqual(abs(metrics.pose(distance: metrics.step).rotation), CoverFlow.sideAngle)
        XCTAssertEqual(metrics.pose(distance: -metrics.step * 3).rotation, CoverFlow.sideAngle)
        // The first side covers stand at their gaps, the third two stack spacings further.
        XCTAssertEqual(drawn(-1), -metrics.firstGap)
        XCTAssertEqual(drawn(-3), -(metrics.firstGap + 2 * metrics.stackSpacing))
        XCTAssertEqual(drawn(1), metrics.rightGap)
        XCTAssertEqual(drawn(3), metrics.rightGap + 2 * metrics.stackSpacing)
    }

    func testCoversSlideInStepWithTheFinger() {
        // No pause in the middle: between the middle and the first side spot a cover moves
        // evenly with the drag.
        let metrics = CoverFlow.Metrics(coverSide: 200)
        for i in 1...9 {
            let fraction = Double(i) / 10
            let right = metrics.step * fraction, left = -right
            XCTAssertEqual(left + metrics.pose(distance: left).xShift, -metrics.firstGap * fraction, accuracy: 1e-9)
            XCTAssertEqual(right + metrics.pose(distance: right).xShift, metrics.rightGap * fraction, accuracy: 1e-9)
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

    /// Rows to check: a tall portrait phone with PSP boxes, landscape with NES-shaped boxes
    /// and the deepest (Atari 7800) boxes, and flat covers.
    private var rows: [CoverFlow.Metrics] {
        [CoverFlow.Metrics.fitting(width: 402, height: 560, tallestAspect: 0.56, deepestBox: 0.16),
         CoverFlow.Metrics.fitting(width: 874, height: 280, tallestAspect: 0.69, deepestBox: 0.16),
         CoverFlow.Metrics.fitting(width: 402, height: 560, tallestAspect: 0.69, deepestBox: 0.05),
         CoverFlow.Metrics(coverSide: 200)]
    }

    private func tallest(_ metrics: CoverFlow.Metrics) -> CoverFlow.Box {
        CoverFlow.Box(width: metrics.coverWidth, height: metrics.coverHeight, depth: metrics.boxDepth)
    }

    private let turns: [Double] = [0, 5, 20, 35, CoverFlow.sideAngle]

    func testRightStackAllButTouchesTheMiddleCover() {
        // Facing right, the first right box's spine turns towards the player beside the middle
        // cover: as the one camera draws them, row by row down the screen, it stops just short
        // of the middle cover's edge, a sliver apart, never over it.
        for metrics in rows {
            let stage = CoverFlow.Stage(metrics: metrics)
            let box = tallest(metrics)
            func drawn(distance: Double) -> [(x: Double, y: Double)] {
                let place = stage.place(distance: distance, height: box.height, depth: box.depth)
                let turn = CoverFlow.Stage.turn(yaw: place.yaw)
                var points: [(x: Double, y: Double)] = []
                for x in [-box.width / 2, box.width / 2] {
                    for y in [-box.height / 2, box.height / 2] {
                        for z in [-box.depth / 2, box.depth / 2] {
                            let q = CoverFlow.apply(turn, (x * place.scale, y * place.scale, z * place.scale))
                            let point = stage.drawn((place.x + q.x, place.y + q.y, place.z + q.z))
                            points.append(point)
                        }
                    }
                }
                return points
            }
            let gap = CoverFlow.closest(drawn(distance: 0), drawn(distance: metrics.step))
            XCTAssertGreaterThanOrEqual(gap, -0.5, "for \(metrics.coverWidth)")
            XCTAssertLessThan(gap, metrics.coverWidth * 0.015, "for \(metrics.coverWidth)")
        }
    }

    func testClosestMeasuresRowByRow() {
        // Two slanted shapes whose nearest corners sit at different heights: the gap is
        // measured along each row, not corner to corner.
        let left: [(x: Double, y: Double)] = [(0, 0), (10, 0), (12, 10), (0, 10)]
        let right: [(x: Double, y: Double)] = [(14, 0), (30, 0), (30, 10), (12.5, 10)]
        XCTAssertEqual(CoverFlow.closest(left, right), 0.5, accuracy: 0.01)
        XCTAssertEqual(CoverFlow.closest(left, [(20, 20), (30, 20), (30, 30)]), .infinity)
        XCTAssertLessThan(CoverFlow.closest(left, [(5, 0), (30, 0), (30, 10), (5, 10)]), 0)
    }

    func testRightNeighbourStandsClearOfTheMiddleBox() {
        // Close as it is, the right neighbour's front face passes in front of the middle box's
        // right edge rather than through it.
        for metrics in rows {
            let stage = CoverFlow.Stage(metrics: metrics)
            let width = metrics.coverWidth, depth = max(metrics.boxDepth, 1), height = metrics.coverHeight
            let middle = stage.place(distance: 0, height: height, depth: depth)
            let right = stage.place(distance: metrics.step, height: height, depth: depth)
            let turn = CoverFlow.Stage.turn(yaw: right.yaw)
            let a = CoverFlow.apply(turn, (-width / 2, 0, depth / 2))
            let b = CoverFlow.apply(turn, (width / 2, 0, depth / 2))
            let edge = middle.x + width / 2 * middle.scale
            let t = (edge - (right.x + a.x)) / (b.x - a.x)
            if t < 0 {
                // Its nearest edge is wholly to the right of the middle box: nothing to meet.
                XCTAssertGreaterThan(right.x + a.x, edge, "for \(width)")
            } else {
                let face = right.z + a.z + min(t, 1) * (b.z - a.z)
                XCTAssertGreaterThan(face, middle.z + depth / 2 * middle.scale, "for \(width)")
            }
        }
    }

    func testLeftCoverStillShowsBesideTheMiddle() {
        // Tucked under the middle cover, the first left box still shows a strip beside it.
        for metrics in rows {
            let middle = metrics.span(tallest(metrics), yaw: 0)
            let flat = CoverFlow.Box(width: metrics.coverWidth, height: metrics.coverHeight, depth: 0)
            let shows = middle.left - (-metrics.firstGap + metrics.span(flat, yaw: CoverFlow.sideAngle).left)
            XCTAssertGreaterThan(shows, metrics.coverWidth * 0.08, "for \(metrics.coverWidth)")
        }
    }

    func testTapsLandOnTheCoverDrawnThere() {
        // A cover's tap area is where it's drawn at rest, not its narrower layout slot: the
        // middle cover's whole front plays it, and the neighbour stacked over its slot (the
        // right stack lies on top) doesn't reach into it.
        for metrics in rows {
            let middle = metrics.restSpan(offset: 0)
            XCTAssertLessThanOrEqual(middle.left, -metrics.coverWidth / 2 + 1e-6)
            XCTAssertGreaterThanOrEqual(middle.right, metrics.coverWidth / 2 - 1e-6)
            let right = metrics.restSpan(offset: 1)
            XCTAssertGreaterThanOrEqual(metrics.step + right.left, middle.right, "for \(metrics.coverWidth)")
            // Its layout slot alone would have reached well into the middle cover.
            XCTAssertLessThan(metrics.step - metrics.coverWidth / 2, middle.right)
            // Covers further out stand further out.
            let left = metrics.restSpan(offset: -1), farLeft = metrics.restSpan(offset: -2)
            XCTAssertLessThan(-metrics.step + left.left, middle.left)
            XCTAssertLessThan(-2 * metrics.step + farLeft.left, -metrics.step + left.left)
        }
    }

    func testCardboardBoxesAreDeeperThanCases() {
        for box in [SystemID.nes, .snes, .n64, .gba, .atari7800] {
            for disc in [SystemID.psp, .nds, .ps1] {
                XCTAssertGreaterThan(CoverFlow.boxDepth(box), CoverFlow.boxDepth(disc))
            }
        }
    }

    func testCoversKeepOneDrawingOrder() {
        // Later games on top, always: no two covers swap places mid-swipe.
        XCTAssertLessThan(CoverFlow.layer(index: 0), CoverFlow.layer(index: 1))
        XCTAssertLessThan(CoverFlow.layer(index: 9), CoverFlow.layer(index: 10))
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

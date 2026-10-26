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
        XCTAssertEqual(metrics.step + metrics.pose(distance: metrics.step).xShift, metrics.firstGap)
        // Was 64% of a cover, then 50%; the stack behind keeps its spacing.
        XCTAssertLessThan(metrics.firstGap, 300 * 0.5)
        let second = metrics.step * 2 + metrics.pose(distance: metrics.step * 2).xShift
        XCTAssertEqual(second - metrics.firstGap, metrics.stackSpacing)
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

    /// Rows to check: a tall portrait phone with PSP boxes, landscape with NES-shaped boxes
    /// and the deepest (Atari 7800) boxes, and flat covers.
    private var rows: [CoverFlow.Metrics] {
        [CoverFlow.Metrics.fitting(width: 402, height: 560, tallestAspect: 0.56, deepestBox: 0.16),
         CoverFlow.Metrics.fitting(width: 874, height: 280, tallestAspect: 0.69, deepestBox: 0.16),
         CoverFlow.Metrics.fitting(width: 402, height: 560, tallestAspect: 0.69, deepestBox: 0.05),
         CoverFlow.Metrics(coverSide: 200)]
    }

    /// Where a point of a face is drawn, from its 3 × 3 transform (relative to the centre).
    private func drawn(_ m: [Double], u: Double, v: Double, width: Double, height: Double) -> (x: Double, y: Double) {
        let x = u * m[0] + v * m[3] + m[6], y = u * m[1] + v * m[4] + m[7], w = u * m[2] + v * m[5] + m[8]
        return (x / w - width / 2, y / w - height / 2)
    }

    func testLeftStackNeverCoversTheMiddleCover() {
        // Facing left, a left box's right side turns towards the player, and the left stack
        // lies on top: the first one stands far enough out that its side, at the deepest box
        // in the row, stops short of the middle cover's edge.
        for metrics in rows {
            let middle = metrics.span(width: metrics.coverWidth, depth: metrics.boxDepth, rotation: 0)
            let side = metrics.span(width: metrics.coverWidth, depth: metrics.boxDepth, rotation: -CoverFlow.sideAngle)
            let pose = metrics.pose(distance: -metrics.step)
            XCTAssertEqual(pose.rotation, -CoverFlow.sideAngle)
            let innerEdge = -metrics.step + pose.xShift + side.right
            XCTAssertLessThanOrEqual(innerEdge, middle.left, "for \(metrics.coverWidth)")
            // And not much further: the stack still reads as one row with the middle.
            XCTAssertLessThan(metrics.leftGap, metrics.coverWidth * 0.95, "for \(metrics.coverWidth)")
        }
    }

    func testRightCoverStillShowsBesideTheMiddle() {
        // Tucked under the middle cover, the first right box (front and side) still shows a
        // strip beside it.
        for metrics in rows {
            let middle = metrics.span(width: metrics.coverWidth, depth: metrics.boxDepth, rotation: 0)
            let side = metrics.span(width: metrics.coverWidth, depth: 0, rotation: -CoverFlow.sideAngle)
            let shows = metrics.firstGap + side.right - middle.right
            XCTAssertGreaterThan(shows, metrics.coverWidth * 0.08, "for \(metrics.coverWidth)")
        }
    }

    func testCoversKeepTheirSize() {
        // No growing into the middle or shrinking away from it: a cover's front is drawn the
        // same height down its centre wherever it stands (perspective aside, within 3%).
        for metrics in rows {
            let width = metrics.coverWidth, height = metrics.coverHeight
            func centreHeight(_ fraction: Double) -> Double {
                let pose = metrics.pose(distance: metrics.step * fraction)
                let m = metrics.faceTransform(.front, width: width, height: height, boxWidth: width,
                                              depth: metrics.boxDepth, rotation: pose.rotation)
                return drawn(m, u: width / 2, v: height, width: width, height: height).y
                    - drawn(m, u: width / 2, v: 0, width: width, height: height).y
            }
            let rest = centreHeight(0)
            XCTAssertEqual(rest, height, accuracy: height * 0.03)
            for fraction in [0.25, 0.5, 1, 3, -0.5, -1, -3] {
                XCTAssertEqual(centreHeight(fraction), rest, accuracy: rest * 0.03, "at \(fraction)")
            }
        }
    }

    func testFlatCoverFacingFrontIsDrawnAsIs() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        let m = metrics.faceTransform(.front, width: 200, height: 300, boxWidth: 200, depth: 0, rotation: 0)
        XCTAssertEqual(m, [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    func testBoxFacesMeetAndMatchTheSpacing() {
        // The side starts where the front ends, and the drawn box reaches exactly as far as
        // the spacing allows for, so what's drawn is what's kept clear.
        for metrics in rows {
            let width = metrics.coverWidth, height = metrics.coverHeight, depth = metrics.boxDepth
            guard depth > 0 else { continue }
            for rotation in [-10.0, -35, -CoverFlow.sideAngle] {
                let front = metrics.faceTransform(.front, width: width, height: height, boxWidth: width,
                                                  depth: depth, rotation: rotation)
                let side = metrics.faceTransform(.side, width: depth, height: height, boxWidth: width,
                                                 depth: depth, rotation: rotation)
                for v in [0, height] {
                    let frontEdge = drawn(front, u: width, v: v, width: width, height: height)
                    let sideEdge = drawn(side, u: 0, v: v, width: depth, height: height)
                    XCTAssertEqual(frontEdge.x, sideEdge.x, accuracy: 1e-6)
                    XCTAssertEqual(frontEdge.y, sideEdge.y, accuracy: 1e-6)
                }
                let span = metrics.span(width: width, depth: depth, rotation: rotation)
                let back = drawn(side, u: depth, v: height / 2, width: depth, height: height)
                let left = drawn(front, u: 0, v: height / 2, width: width, height: height)
                XCTAssertEqual(back.x, span.right, accuracy: 1e-6)
                XCTAssertEqual(left.x, span.left, accuracy: 1e-6)
            }
        }
    }

    func testRotationsDrawTheFacesWhereTheBoxPlacesThem() {
        // The view draws each face with a 3D rotation about the vertical axis, anchored at the
        // face's centre and `anchorZ` behind it, the eye `max(width, height) / perspective`
        // from the anchor (SwiftUI's rotation3DEffect). Those land each point where the box
        // geometry (and so the spacing) puts it.
        for metrics in rows {
            let width = metrics.coverWidth, height = metrics.coverHeight, depth = max(metrics.boxDepth, 12)
            for rotation in [0.0, -10, -35, -CoverFlow.sideAngle] {
                for (face, faceWidth) in [(CoverFlow.Face.front, width), (.side, depth)] {
                    let turn = metrics.faceRotation(face, boxWidth: width, depth: depth, rotation: rotation)
                    let eye = max(faceWidth, height) / metrics.facePerspective(width: faceWidth, height: height)
                    let m = metrics.faceTransform(face, width: faceWidth, height: height, boxWidth: width,
                                                  depth: depth, rotation: rotation)
                    let angle = -turn.angle * .pi / 180
                    for (u, v) in [(0.0, 0.0), (faceWidth, height), (faceWidth / 3, height / 2)] {
                        let x = u - faceWidth / 2, y = v - height / 2, z = -turn.anchorZ
                        let turnedX = cos(angle) * x - sin(angle) * z
                        let turnedZ = sin(angle) * x + cos(angle) * z
                        let k = eye / (eye - turnedZ)
                        let expected = drawn(m, u: u, v: v, width: faceWidth, height: height)
                        XCTAssertEqual(turnedX * k, expected.x, accuracy: 1e-6, "\(face) at \(rotation)")
                        XCTAssertEqual(y * k, expected.y, accuracy: 1e-6, "\(face) at \(rotation)")
                    }
                }
            }
        }
    }

    func testSideShowsOnlyOnceTurned() {
        // Facing the player the side folds back behind the front's edge (hidden under it);
        // turned, it opens out.
        let metrics = CoverFlow.Metrics(coverWidth: 200, coverHeight: 280, boxDepth: 30)
        func sideWidth(_ rotation: Double) -> Double {
            let m = metrics.faceTransform(.side, width: 30, height: 280, boxWidth: 200, depth: 30, rotation: rotation)
            return drawn(m, u: 30, v: 140, width: 30, height: 280).x - drawn(m, u: 0, v: 140, width: 30, height: 280).x
        }
        XCTAssertLessThanOrEqual(sideWidth(0), 0)
        XCTAssertGreaterThan(sideWidth(-35), 10)
        XCTAssertGreaterThan(sideWidth(-CoverFlow.sideAngle), sideWidth(-35))
    }

    func testTurnedCoversStayWithinTheOverhang() {
        // A turned box's nearest edge is drawn taller than the slot; `overhang` covers it, so
        // the room left below the row keeps covers off the caption.
        for metrics in rows {
            let width = metrics.coverWidth, height = metrics.coverHeight, depth = metrics.boxDepth
            var lowest = 0.0
            for degrees in stride(from: 0.0, through: CoverFlow.sideAngle, by: 5) {
                let faces = depth > 0 ? [(CoverFlow.Face.front, width), (.side, depth)] : [(.front, width)]
                for (face, faceWidth) in faces {
                    let m = metrics.faceTransform(face, width: faceWidth, height: height, boxWidth: width,
                                                  depth: metrics.boxDepth, rotation: -degrees)
                    for u in [0, faceWidth] {
                        lowest = max(lowest, drawn(m, u: u, v: height, width: faceWidth, height: height).y)
                    }
                }
            }
            XCTAssertGreaterThan(metrics.overhang, 0)
            XCTAssertLessThanOrEqual(lowest, height / 2 + metrics.overhang + 0.5, "for \(width)")
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

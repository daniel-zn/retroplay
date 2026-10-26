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

    private func tallest(_ metrics: CoverFlow.Metrics) -> CoverFlow.Box {
        CoverFlow.Box(width: metrics.coverWidth, height: metrics.coverHeight, depth: metrics.boxDepth)
    }

    private let turns: [Double] = [0, -5, -20, -35, -CoverFlow.sideAngle]

    func testLeftStackNeverCoversTheMiddleCover() {
        // Facing left, a left box's right side turns towards the player, and the left stack
        // lies on top: the first one stands far enough out that its side, at the deepest box
        // in the row, stops short of the middle cover's edge.
        for metrics in rows {
            let middle = metrics.span(tallest(metrics), yaw: 0)
            let side = metrics.span(tallest(metrics), yaw: -CoverFlow.sideAngle)
            let pose = metrics.pose(distance: -metrics.step)
            XCTAssertEqual(pose.rotation, -CoverFlow.sideAngle)
            let innerEdge = -metrics.step + pose.xShift + side.right
            XCTAssertLessThanOrEqual(innerEdge, middle.left, "for \(metrics.coverWidth)")
            // And not much further: the stack still reads as one row with the middle.
            XCTAssertLessThan(metrics.leftGap, metrics.coverWidth * 0.95, "for \(metrics.coverWidth)")
        }
    }

    func testRightCoverStillShowsBesideTheMiddle() {
        // Tucked under the middle cover, the first right box still shows a strip beside it.
        for metrics in rows {
            let middle = metrics.span(tallest(metrics), yaw: 0)
            let flat = CoverFlow.Box(width: metrics.coverWidth, height: metrics.coverHeight, depth: 0)
            let shows = metrics.firstGap + metrics.span(flat, yaw: -CoverFlow.sideAngle).right - middle.right
            XCTAssertGreaterThan(shows, metrics.coverWidth * 0.08, "for \(metrics.coverWidth)")
        }
    }

    func testCoversKeepTheirSize() {
        // No growing into the middle or shrinking away from it: a cover's front is drawn the
        // same height down its centre wherever it stands (perspective aside, within 3%).
        for metrics in rows {
            let box = tallest(metrics)
            func centreHeight(_ yaw: Double) -> Double {
                metrics.drawn(.front, box, yaw: yaw, u: box.width / 2, v: box.height).y
                    - metrics.drawn(.front, box, yaw: yaw, u: box.width / 2, v: 0).y
            }
            let rest = centreHeight(0)
            // Tipped back, the middle cover's front is drawn a touch shorter than it is.
            XCTAssertEqual(rest, box.height, accuracy: box.height * 0.06)
            for yaw in turns {
                XCTAssertEqual(centreHeight(yaw), rest, accuracy: rest * 0.03, "at \(yaw)")
            }
        }
    }

    func testABoxShowsItsFrontSideAndTop() {
        // A whole box: turned left and seen a little from above, its front, right side and
        // top face the player; the back, left side and bottom face away.
        XCTAssertLessThan(CoverFlow.pitch, 0)
        let metrics = CoverFlow.Metrics.fitting(width: 402, height: 560, deepestBox: 0.15)
        let box = tallest(metrics)
        // Turned far enough for the side to clear the eye (at 5° the box still hides it).
        for yaw in turns.dropFirst(2) {
            for face in [CoverFlow.Face.front, .right, .top] {
                XCTAssertTrue(metrics.isFacing(face, box, yaw: yaw), "\(face) at \(yaw)")
            }
            for face in [CoverFlow.Face.back, .left, .bottom] {
                XCTAssertFalse(metrics.isFacing(face, box, yaw: yaw), "\(face) at \(yaw)")
            }
        }
        // Facing the player, the side is edge-on: hidden.
        XCTAssertFalse(metrics.isFacing(.right, box, yaw: 0))
        XCTAssertTrue(metrics.isFacing(.top, box, yaw: 0))
        XCTAssertEqual(Set(CoverFlow.shownFaces), [.front, .right, .top])
    }

    func testFacesMeetAtTheBoxsEdges() {
        // The front's top right corner, the side's top front corner and the top's front right
        // corner are one point, wherever the box turns; so are the edges between them.
        for metrics in rows {
            let box = tallest(metrics)
            guard box.depth > 0 else { continue }
            for yaw in turns {
                let corner = metrics.drawn(.front, box, yaw: yaw, u: box.width, v: 0)
                let side = metrics.drawn(.right, box, yaw: yaw, u: 0, v: 0)
                let top = metrics.drawn(.top, box, yaw: yaw, u: box.width, v: box.depth)
                for other in [side, top] {
                    XCTAssertEqual(other.x, corner.x, accuracy: 1e-6, "at \(yaw)")
                    XCTAssertEqual(other.y, corner.y, accuracy: 1e-6, "at \(yaw)")
                }
                // The side's back top corner is the top's back right corner.
                let sideBack = metrics.drawn(.right, box, yaw: yaw, u: box.depth, v: 0)
                let topBack = metrics.drawn(.top, box, yaw: yaw, u: box.width, v: 0)
                XCTAssertEqual(sideBack.x, topBack.x, accuracy: 1e-6)
                XCTAssertEqual(sideBack.y, topBack.y, accuracy: 1e-6)
            }
        }
    }

    func testRotationsDrawTheFacesWhereTheBoxPlacesThem() {
        // The view turns each face with one rotation3DEffect (an axis and an angle, anchored at
        // its centre and `anchorZ` behind it, the eye `max(width, height) / perspective` from
        // the anchor). That lands every point where the box model puts it, for every face.
        for metrics in rows {
            let box = CoverFlow.Box(width: metrics.coverWidth, height: metrics.coverHeight,
                                    depth: max(metrics.boxDepth, 12))
            for yaw in turns {
                for face in CoverFlow.Face.allCases {
                    let size = CoverFlow.faceSize(face, box)
                    let turn = metrics.faceTurn(face, box, yaw: yaw)
                    let eye = max(size.width, size.height) / metrics.facePerspective(width: size.width, height: size.height)
                    let m = CoverFlow.rotation(axis: turn.axis, degrees: turn.degrees)
                    // The anchor, from the face's (and the box's) centre.
                    let anchorY = (turn.anchorY - 0.5) * size.height
                    for (u, v) in [(0.0, 0.0), (size.width, size.height), (size.width / 3, size.height / 2)] {
                        // The point, moved by `shift`, relative to the anchor (anchorZ behind it).
                        let p = (x: u - size.width / 2 + turn.shift.x,
                                 y: v - size.height / 2 + turn.shift.y - anchorY,
                                 z: -turn.anchorZ)
                        let q = CoverFlow.apply(m, p)
                        let k = eye / (eye - q.z)
                        let expected = metrics.drawn(face, box, yaw: yaw, u: u, v: v)
                        XCTAssertEqual(q.x * k, expected.x, accuracy: 1e-6, "\(face) at \(yaw)")
                        XCTAssertEqual(anchorY + q.y * k, expected.y, accuracy: 1e-6, "\(face) at \(yaw)")
                    }
                }
            }
        }
    }

    func testSpacingMatchesTheDrawnBox() {
        // The box's reach used for spacing is exactly as far as its shown faces are drawn.
        for metrics in rows {
            let box = tallest(metrics)
            for yaw in turns {
                var xs: [Double] = []
                for face in CoverFlow.Face.allCases where metrics.isFacing(face, box, yaw: yaw) {
                    let size = CoverFlow.faceSize(face, box)
                    for u in [0, size.width] { for v in [0, size.height] {
                        xs.append(metrics.drawn(face, box, yaw: yaw, u: u, v: v).x)
                    } }
                }
                let span = metrics.span(box, yaw: yaw)
                XCTAssertEqual(xs.max() ?? 0, span.right, accuracy: 1e-6, "at \(yaw)")
                XCTAssertEqual(xs.min() ?? 0, span.left, accuracy: 1e-6, "at \(yaw)")
            }
        }
    }

    func testTurnedCoversStayWithinTheOverhang() {
        // Tipped back and in perspective, a box reaches past its slot; `overhang` covers it, so
        // the room left above and below the row keeps covers off the caption.
        for metrics in rows {
            let box = tallest(metrics)
            var reach = 0.0
            for yaw in stride(from: -CoverFlow.sideAngle, through: 0, by: 5) {
                for face in CoverFlow.Face.allCases where metrics.isFacing(face, box, yaw: yaw) {
                    let size = CoverFlow.faceSize(face, box)
                    for u in [0, size.width] { for v in [0, size.height] {
                        reach = max(reach, abs(metrics.drawn(face, box, yaw: yaw, u: u, v: v).y))
                    } }
                }
            }
            XCTAssertGreaterThan(metrics.overhang, 0)
            XCTAssertLessThanOrEqual(reach, box.height / 2 + metrics.overhang + 0.5, "for \(box.width)")
        }
    }

    func testAxisAndAngleGiveBackTheTurn() {
        for axis in [(x: 1.0, y: 0.0, z: 0.0), (0, 1, 0), (0.3, -0.8, 0.2)] {
            for degrees in [0.0, 10, 90, 135, 180] {
                let m = CoverFlow.rotation(axis: axis, degrees: degrees)
                let back = CoverFlow.axisAngle(m)
                let again = CoverFlow.rotation(axis: back.axis, degrees: back.degrees)
                for r in 0..<3 { for c in 0..<3 { XCTAssertEqual(again[r][c], m[r][c], accuracy: 1e-6) } }
            }
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

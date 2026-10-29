// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class CoverFlowStageTests: XCTestCase {
    private let stages = [
        CoverFlow.Stage(metrics: .fitting(width: 402, height: 560, tallestAspect: 0.56, deepestBox: 0.16)),
        CoverFlow.Stage(metrics: .fitting(width: 874, height: 300, tallestAspect: 0.69, deepestBox: 0.16)),
        CoverFlow.Stage(metrics: CoverFlow.Metrics(coverSide: 200)),
    ]

    /// Where a box's front is drawn down its centre line (top and bottom, y up), turned `yaw`.
    private func front(_ stage: CoverFlow.Stage, height: Double, depth: Double, distance: Double = 0)
        -> (top: Double, bottom: Double)
    {
        let place = stage.place(distance: distance, height: height, depth: depth)
        let turn = CoverFlow.Stage.turn(yaw: place.yaw)
        func at(_ y: Double) -> Double {
            let p = CoverFlow.apply(turn, (0, y * place.scale, depth / 2 * place.scale))
            return stage.drawn((place.x + p.x, place.y + p.y, place.z + p.z)).y
        }
        return (at(height / 2), at(-height / 2))
    }

    func testTheMiddleBoxFrontStandsWhereTheFlatCoverDid() {
        // Seen from above and tipped back, the box is raised so its front's middle is drawn on
        // the flat cover's middle (standing on the slot's floor).
        for stage in stages {
            for (height, depth) in [(stage.metrics.coverHeight, 30.0), (stage.metrics.coverHeight * 0.6, 12), (180, 0)] {
                let drawn = front(stage, height: height, depth: depth)
                let flat = -stage.metrics.coverHeight / 2 + height / 2
                XCTAssertEqual((drawn.top + drawn.bottom) / 2, flat, accuracy: 1e-6, "\(height) × \(depth)")
            }
        }
    }

    func testCoversKeepTheirSizeAsTheyTurn() {
        // No growing into the middle or shrinking away: the front's height down its centre stays
        // within a few percent wherever the cover stands.
        for stage in stages {
            let height = stage.metrics.coverHeight, depth = 30.0
            let rest = front(stage, height: height, depth: depth)
            for fraction in [0.25, 0.5, 1, 3, -0.5, -1, -3] {
                let turned = front(stage, height: height, depth: depth, distance: stage.metrics.step * fraction)
                XCTAssertEqual(turned.top - turned.bottom, rest.top - rest.bottom,
                               accuracy: (rest.top - rest.bottom) * 0.06, "at \(fraction)")
            }
        }
    }

    func testBoxesStandWhereTheRowPutsThem() {
        for stage in stages {
            let metrics = stage.metrics
            for fraction in [0.0, 0.5, 1, -1, 3, -3] {
                let distance = metrics.step * fraction
                let pose = metrics.pose(distance: distance)
                let place = stage.place(distance: distance, height: 200, depth: 20)
                // Slid towards the eye and scaled to match, it's drawn where the row puts it.
                XCTAssertEqual(stage.drawn((place.x, 0, place.z)).x, distance + pose.xShift, accuracy: 1e-9)
                XCTAssertEqual(place.yaw, pose.rotation, accuracy: 1e-9)
                XCTAssertEqual(place.dimming, pose.dimming, accuracy: 1e-9)
            }
        }
    }

    func testTheMiddleCoverStandsClearInFrontOfTheLeftStack() {
        // The first left cover faces right, its near (spine) edge turned towards the player
        // beside the middle cover: the middle box stands far enough forward that its back is
        // in front of that cover's front face all along the middle cover's width.
        for stage in stages {
            let metrics = stage.metrics
            let width = metrics.coverWidth, depth = metrics.boxDepth, height = metrics.coverHeight
            let middle = stage.place(distance: 0, height: height, depth: depth)
            let left = stage.place(distance: -metrics.step, height: height, depth: depth)
            XCTAssertGreaterThan(middle.z, 0)
            XCTAssertEqual(left.z, 0, accuracy: 1e-9)
            // The left cover's front face, as a line across the floor (x, z).
            let turn = CoverFlow.Stage.turn(yaw: left.yaw)
            let a = CoverFlow.apply(turn, (-width / 2, 0, depth / 2))
            let b = CoverFlow.apply(turn, (width / 2, 0, depth / 2))
            let back = middle.z - depth / 2 * middle.scale
            for i in 0...10 {
                let x = middle.x - width / 2 * middle.scale + Double(i) / 10 * width * middle.scale
                let t = (x - (left.x + a.x)) / (b.x - a.x)
                guard t >= 0, t <= 1 else { continue }
                let face = left.z + a.z + t * (b.z - a.z)
                XCTAssertGreaterThan(back, face, "at x \(x) for \(width)")
            }
        }
    }

    func testStandingForwardDoesNotChangeHowTheMiddleCoverIsDrawn() {
        for stage in stages {
            let flat = CoverFlow.Stage(metrics: stage.metrics)
            let place = stage.place(distance: 0, height: 200, depth: 20)
            // Its corners, nearer and smaller, land where they would standing in the row.
            for (x, y) in [(-100.0, -100.0), (100, 100), (0, 50)] {
                let near = stage.drawn((place.x + x * place.scale,
                                        place.y + y * place.scale, place.z))
                let unscaledY = (place.y - flat.eyeHeight) / place.scale + flat.eyeHeight
                let row = flat.drawn((place.x / place.scale + x, unscaledY + y, 0))
                XCTAssertEqual(near.x, row.x, accuracy: 1e-6)
                XCTAssertEqual(near.y, row.y, accuracy: 1e-6)
            }
        }
    }

    func testTheCameraDrawsTheRowAtItsOwnSize() {
        // The view's edge, half its height from the eye, is where the camera's field of view
        // ends: the slot's plane is drawn point for point.
        for stage in stages {
            let height = 900.0
            let half = tan(stage.fieldOfView(height: height) / 2 * .pi / 180) * stage.eyeDistance
            XCTAssertEqual(half, height / 2, accuracy: 1e-6)
            let edge = stage.drawn((0, stage.eyeHeight + height / 2, 0))
            XCTAssertEqual(edge.y - stage.eyeHeight, height / 2, accuracy: 1e-9)
        }
    }

    func testOnlyTheCoversInViewAreBuilt() {
        // Every cover that reaches into the view is in the window; far ones aren't, so a long
        // library builds a handful of boxes.
        for stage in stages {
            let metrics = stage.metrics, width = 874.0, count = 200
            let offset = metrics.step * 100
            let window = stage.window(offset: offset, count: count, width: width)
            for index in 0..<count {
                let place = stage.place(distance: Double(index) * metrics.step - offset, height: 100, depth: 10)
                if abs(place.x) - metrics.coverWidth < width / 2 {
                    XCTAssertTrue(window.contains(index), "cover \(index) reaches into view")
                }
            }
            XCTAssertLessThan(window.count, 60)
            XCTAssertEqual(stage.window(offset: 0, count: 0, width: width), 0..<0)
            XCTAssertEqual(stage.window(offset: 0, count: 3, width: width).lowerBound, 0)
            XCTAssertEqual(stage.window(offset: metrics.step * 2, count: 3, width: width).upperBound, 3)
        }
    }
}

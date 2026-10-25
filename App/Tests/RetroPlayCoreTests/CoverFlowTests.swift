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
        // Portrait phone: the width limits it.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 390, height: 420).coverSide, 218)
        // Landscape: the height does.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 180).coverSide, 180)
        // Never below the minimum, even with large text squeezing the space.
        XCTAssertEqual(CoverFlow.Metrics.fitting(width: 750, height: 40).coverSide, 110)
    }

    func testSideCoversStack() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        XCTAssertLessThan(metrics.step, metrics.coverSide / 2)
        XCTAssertGreaterThan(metrics.firstGap, metrics.coverSide / 2)
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
        XCTAssertEqual(third.xShift, first.xShift)
        // The first side cover stands `firstGap` from the middle.
        XCTAssertEqual(metrics.step + first.xShift, metrics.firstGap)
    }

    func testTurningIsContinuousThroughTheMiddle() {
        let metrics = CoverFlow.Metrics(coverSide: 200)
        let half = metrics.pose(distance: metrics.step / 2)
        XCTAssertEqual(abs(half.rotation), CoverFlow.sideAngle / 2, accuracy: 1e-9)
        XCTAssertLessThan(abs(metrics.pose(distance: 1).rotation), 2)
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

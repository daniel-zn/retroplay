// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// The landscape bottom-centre row: the small buttons split evenly either side of fast-forward
/// / pause / sound, and the room a fitted picture leaves it.
final class LandscapeCentreRowTests: XCTestCase {
    func testSelectGoesLeftAndStartRight() {
        let split = LandscapeCentreRow.split(["SELECT", "START"])
        XCTAssertEqual(split.left, ["SELECT"])
        XCTAssertEqual(split.right, ["START"])
    }

    func testALoneStartGoesRight() {
        let split = LandscapeCentreRow.split(["START"])
        XCTAssertEqual(split.left, [])
        XCTAssertEqual(split.right, ["START"])
    }

    func testTheAtariSwitchesSplitOneAndTwoInOrder() {
        let split = LandscapeCentreRow.split(["SELECT", "PAUSE", "RESET"])
        XCTAssertEqual(split.left, ["SELECT"])
        XCTAssertEqual(split.right, ["PAUSE", "RESET"])
    }

    func testStylesGetSmallerSoANarrowGapStillFits() {
        let widths = LandscapeCentreRow.styles.map { 3 * $0.buttonWidth + 2 * $0.buttonSpacing + 2 * $0.sideSpacing }
        XCTAssertEqual(widths, widths.sorted(by: >))
        // iPhone SE landscape (667 pt) with the widest columns (168 pt, 8 pt in): the smallest
        // style leaves room for a small button either side.
        let gap = LandscapeCentreRow.gap(width: 667, columnWidth: 168, edgeInset: 8)
        XCTAssertGreaterThan(gap - widths.last!, 2 * 60, "gap \(gap)")
    }

    func testAFittedPictureGivesUpOnlyWhatTheHomeStripDoesNot() {
        XCTAssertEqual(LandscapeCentreRow.pictureReserve(bottomSafeArea: 21), 27)
        XCTAssertEqual(LandscapeCentreRow.pictureReserve(bottomSafeArea: 0), 48)
        XCTAssertEqual(LandscapeCentreRow.pictureReserve(bottomSafeArea: 60), 0)
    }
}

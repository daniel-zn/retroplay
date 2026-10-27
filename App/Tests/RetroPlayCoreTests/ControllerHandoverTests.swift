// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class ControllerHandoverTests: XCTestCase {
    func testTouchControlsFadeQuickly() {
        // A visible fade, but quick: the player is mid-game.
        XCTAssertGreaterThan(ControllerHandover.fade, 0.1)
        XCTAssertLessThanOrEqual(ControllerHandover.fade, 0.35)
    }

    func testLosingTheControllerKeepsTheGameRunning() {
        XCTAssertFalse(ControllerHandover.pausesOnDisconnect)
    }

    func testTouchControlsShowWithoutAController() {
        XCTAssertTrue(ControllerHandover.showsTouchControls(hasController: false, touchWithController: false))
        XCTAssertFalse(ControllerHandover.showsTouchControls(hasController: true, touchWithController: false))
        XCTAssertTrue(ControllerHandover.showsTouchControls(hasController: true, touchWithController: true))
        XCTAssertTrue(ControllerHandover.showsTouchControls(hasController: false, touchWithController: true))
    }
}

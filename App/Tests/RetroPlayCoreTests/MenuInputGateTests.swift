// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Pause-menu presses made with a controller don't reach the game.
final class MenuInputGateTests: XCTestCase {
    func testMenuOpenSendsNothingToTheGame() {
        var gate = MenuInputGate()
        _ = gate.setMenuOpen(true)
        XCTAssertEqual(gate.filter(PhysicalPadState(roles: .south, leftStickX: 1)), .neutral)
    }

    func testButtonHeldWhenTheMenuClosesStaysOutUntilReleased() {
        var gate = MenuInputGate()
        _ = gate.setMenuOpen(true)
        _ = gate.filter(PhysicalPadState(roles: .south))
        // A on Resume: the menu closes with A still down.
        XCTAssertEqual(gate.setMenuOpen(false).roles, [])
        // Another button pressed meanwhile goes through; A is still held and still out.
        XCTAssertEqual(gate.filter(PhysicalPadState(roles: [.south, .east])).roles, .east)
        // Released, then pressed again: now it's a real press.
        XCTAssertEqual(gate.filter(.neutral).roles, [])
        XCTAssertEqual(gate.filter(PhysicalPadState(roles: .south)).roles, .south)
    }

    func testSticksPassOnceTheMenuIsClosed() {
        var gate = MenuInputGate()
        _ = gate.setMenuOpen(true)
        _ = gate.filter(PhysicalPadState(roles: .east, leftStickX: 0.8))
        let after = gate.setMenuOpen(false)
        XCTAssertEqual(after.leftStickX, 0.8)
        XCTAssertEqual(after.roles, [])
    }
}

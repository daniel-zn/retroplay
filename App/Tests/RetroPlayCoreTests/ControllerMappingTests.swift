// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class ControllerMappingTests: XCTestCase {
    func testGBAFaceButtonsArePositional() {
        let pad = PhysicalPadState(roles: [.east, .south])
        let mapped = ControllerMapping.map(pad, for: .gba)
        XCTAssertEqual(mapped.buttons, UInt32(GBAInput([.a, .b]).rawValue))
    }

    func testGBALeftStickActsAsDPad() {
        let pad = PhysicalPadState(leftStickX: -0.9, leftStickY: 0.8)
        let mapped = ControllerMapping.map(pad, for: .gba)
        XCTAssertEqual(mapped.buttons, UInt32(GBAInput([.left, .up]).rawValue))
    }

    func testPSPKeepsAnalogAndMapsDiamond() {
        let pad = PhysicalPadState(roles: [.south, .north], leftStickX: 0.25, leftStickY: -0.5)
        let mapped = ControllerMapping.map(pad, for: .psp)
        XCTAssertEqual(mapped.buttons, PSPInput([.cross, .triangle]).rawValue)
        XCTAssertEqual(mapped.analogX, 0.25)
        XCTAssertEqual(mapped.analogY, -0.5)
    }

    func testN64RightStickDrivesCButtons() {
        let pad = PhysicalPadState(roles: [.south, .leftTrigger], rightStickX: 1, rightStickY: 0)
        let mapped = ControllerMapping.map(pad, for: .n64)
        XCTAssertEqual(mapped.buttons, N64Input([.a, .z, .cRight]).rawValue)
    }

    func testNDSDiamond() {
        let pad = PhysicalPadState(roles: [.north, .west, .start])
        let mapped = ControllerMapping.map(pad, for: .nds)
        XCTAssertEqual(mapped.buttons, NDSInput([.x, .y, .start]).rawValue)
    }

    func testInputStateAnalogInt8() {
        let state = EmulatorInputState(analogX: 1, analogY: -0.5)
        let v = state.analogInt8()
        XCTAssertEqual(v.x, 80)
        XCTAssertEqual(v.y, -40)
    }
}

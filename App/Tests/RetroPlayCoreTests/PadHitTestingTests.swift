import XCTest
@testable import RetroPlayCore

final class PadHitTestingTests: XCTestCase {
    func testDpadNeutralInsideDeadzone() {
        let bits = PadHitTesting.dpad(dx: 3, dy: -4, deadzone: 10)
        XCTAssertFalse(bits.up)
        XCTAssertFalse(bits.down)
        XCTAssertFalse(bits.left)
        XCTAssertFalse(bits.right)
    }

    func testDpadCardinals() {
        let up = PadHitTesting.dpad(dx: 0, dy: -40)
        XCTAssertTrue(up.up)
        XCTAssertFalse(up.down || up.left || up.right)

        let down = PadHitTesting.dpad(dx: 0, dy: 40)
        XCTAssertTrue(down.down)
        XCTAssertFalse(down.up || down.left || down.right)

        let left = PadHitTesting.dpad(dx: -40, dy: 0)
        XCTAssertTrue(left.left)
        XCTAssertFalse(left.up || left.down || left.right)

        let right = PadHitTesting.dpad(dx: 40, dy: 0)
        XCTAssertTrue(right.right)
        XCTAssertFalse(right.up || right.down || right.left)
    }

    func testDpadDiagonal() {
        let bits = PadHitTesting.dpad(dx: 40, dy: -40)
        XCTAssertTrue(bits.up && bits.right)
        XCTAssertFalse(bits.down || bits.left)
    }

    func testAnalogCenteredDeadzone() {
        let sample = PadHitTesting.analog(dx: 2, dy: 2, radius: 48)
        XCTAssertEqual(sample.x, 0)
        XCTAssertEqual(sample.y, 0)
    }

    func testAnalogMapsScreenYDownToStickYUp() {
        let up = PadHitTesting.analog(dx: 0, dy: -48, radius: 48, maxMagnitude: 80)
        XCTAssertEqual(up.x, 0)
        XCTAssertEqual(up.y, 80)

        let down = PadHitTesting.analog(dx: 0, dy: 48, radius: 48, maxMagnitude: 80)
        XCTAssertEqual(down.y, -80)

        let right = PadHitTesting.analog(dx: 48, dy: 0, radius: 48, maxMagnitude: 80)
        XCTAssertEqual(right.x, 80)
        XCTAssertEqual(right.y, 0)
    }

    func testAnalogClampsToCircle() {
        let sample = PadHitTesting.analog(dx: 80, dy: -80, radius: 48, maxMagnitude: 80)
        let mag = (Double(sample.x) * Double(sample.x) + Double(sample.y) * Double(sample.y)).squareRoot()
        XCTAssertLessThanOrEqual(mag, 80 + 1)
        XCTAssertGreaterThan(sample.x, 0)
        XCTAssertGreaterThan(sample.y, 0)
    }

    func testNDSTouchMapsRect() {
        let origin = PadHitTesting.ndsTouch(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 0)

        let far = PadHitTesting.ndsTouch(x: 200, y: 100, width: 200, height: 100)
        XCTAssertEqual(far.x, 255)
        XCTAssertEqual(far.y, 191)

        let mid = PadHitTesting.ndsTouch(x: 100, y: 50, width: 200, height: 100)
        XCTAssertEqual(mid.x, 127)
        XCTAssertEqual(mid.y, 95)
    }

    func testNDSTouchClampsOutside() {
        let sample = PadHitTesting.ndsTouch(x: -10, y: 400, width: 100, height: 80)
        XCTAssertEqual(sample.x, 0)
        XCTAssertEqual(sample.y, 191)
    }

    func testAnalogProducesN64StickRange() {
        let sample = PadHitTesting.analog(dx: 24, dy: -24, radius: 48, maxMagnitude: 80)
        let stick = N64AnalogStick(x: sample.x, y: sample.y)
        XCTAssertGreaterThan(stick.x, 0)
        XCTAssertGreaterThan(stick.y, 0)
        XCTAssertLessThanOrEqual(abs(Int(stick.x)), 80)
        XCTAssertLessThanOrEqual(abs(Int(stick.y)), 80)
    }
}

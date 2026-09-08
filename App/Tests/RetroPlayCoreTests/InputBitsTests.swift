import XCTest
@testable import RetroPlayCore

/// Guard the console bit layouts the pads still write through ConsolePadHost.
final class InputBitsTests: XCTestCase {
    func testGBABits() {
        XCTAssertEqual(GBAInput.a.rawValue, 1 << 0)
        XCTAssertEqual(GBAInput.b.rawValue, 1 << 1)
        XCTAssertEqual(GBAInput.select.rawValue, 1 << 2)
        XCTAssertEqual(GBAInput.start.rawValue, 1 << 3)
        XCTAssertEqual(GBAInput.right.rawValue, 1 << 4)
        XCTAssertEqual(GBAInput.left.rawValue, 1 << 5)
        XCTAssertEqual(GBAInput.up.rawValue, 1 << 6)
        XCTAssertEqual(GBAInput.down.rawValue, 1 << 7)
        XCTAssertEqual(GBAInput.r.rawValue, 1 << 8)
        XCTAssertEqual(GBAInput.l.rawValue, 1 << 9)
    }

    func testPSPBitsMatchPPSSPPCtrl() {
        XCTAssertEqual(PSPInput.select.rawValue, 0x0001)
        XCTAssertEqual(PSPInput.start.rawValue, 0x0008)
        XCTAssertEqual(PSPInput.up.rawValue, 0x0010)
        XCTAssertEqual(PSPInput.right.rawValue, 0x0020)
        XCTAssertEqual(PSPInput.down.rawValue, 0x0040)
        XCTAssertEqual(PSPInput.left.rawValue, 0x0080)
        XCTAssertEqual(PSPInput.l.rawValue, 0x0100)
        XCTAssertEqual(PSPInput.r.rawValue, 0x0200)
        XCTAssertEqual(PSPInput.triangle.rawValue, 0x1000)
        XCTAssertEqual(PSPInput.circle.rawValue, 0x2000)
        XCTAssertEqual(PSPInput.cross.rawValue, 0x4000)
        XCTAssertEqual(PSPInput.square.rawValue, 0x8000)
    }

    func testN64BitsMatchMupenPlugin() {
        XCTAssertEqual(N64Input.dpadRight.rawValue, 0x0001)
        XCTAssertEqual(N64Input.dpadLeft.rawValue, 0x0002)
        XCTAssertEqual(N64Input.dpadDown.rawValue, 0x0004)
        XCTAssertEqual(N64Input.dpadUp.rawValue, 0x0008)
        XCTAssertEqual(N64Input.start.rawValue, 0x0010)
        XCTAssertEqual(N64Input.l.rawValue, 0x0020)
        XCTAssertEqual(N64Input.cRight.rawValue, 0x0100)
        XCTAssertEqual(N64Input.cLeft.rawValue, 0x0200)
        XCTAssertEqual(N64Input.cDown.rawValue, 0x0400)
        XCTAssertEqual(N64Input.cUp.rawValue, 0x0800)
        XCTAssertEqual(N64Input.r.rawValue, 0x1000)
        XCTAssertEqual(N64Input.z.rawValue, 0x2000)
        XCTAssertEqual(N64Input.b.rawValue, 0x4000)
        XCTAssertEqual(N64Input.a.rawValue, 0x8000)
    }

    func testNDSBitsMatchMelonDSOrder() {
        XCTAssertEqual(NDSInput.a.rawValue, 1 << 0)
        XCTAssertEqual(NDSInput.b.rawValue, 1 << 1)
        XCTAssertEqual(NDSInput.select.rawValue, 1 << 2)
        XCTAssertEqual(NDSInput.start.rawValue, 1 << 3)
        XCTAssertEqual(NDSInput.right.rawValue, 1 << 4)
        XCTAssertEqual(NDSInput.left.rawValue, 1 << 5)
        XCTAssertEqual(NDSInput.up.rawValue, 1 << 6)
        XCTAssertEqual(NDSInput.down.rawValue, 1 << 7)
        XCTAssertEqual(NDSInput.r.rawValue, 1 << 8)
        XCTAssertEqual(NDSInput.l.rawValue, 1 << 9)
        XCTAssertEqual(NDSInput.x.rawValue, 1 << 10)
        XCTAssertEqual(NDSInput.y.rawValue, 1 << 11)
    }
}

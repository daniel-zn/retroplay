import XCTest
@testable import RetroPlayCore

final class GBAInputTests: XCTestCase {
    func testOptionSetUnion() {
        let held: GBAInput = [.a, .left]
        XCTAssertTrue(held.contains(.a))
        XCTAssertTrue(held.contains(.left))
        XCTAssertFalse(held.contains(.b))
    }

    func testGroups() {
        XCTAssertTrue(GBAInput.dpad.contains(.up))
        XCTAssertTrue(GBAInput.face.contains(.start))
    }
}

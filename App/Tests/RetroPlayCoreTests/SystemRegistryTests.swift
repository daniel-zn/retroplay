import XCTest
@testable import RetroPlayCore

final class SystemRegistryTests: XCTestCase {
    func testExtensionsMapToP0Systems() {
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "gba"), .gba)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: ".GBA"), .gba)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "z64"), .n64)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "nds"), .nds)
        XCTAssertEqual(SystemRegistry.system(forFileExtension: "cso"), .psp)
        XCTAssertNil(SystemRegistry.system(forFileExtension: "exe"))
    }

    func testDefaultCoreNames() {
        XCTAssertEqual(SystemID.gba.defaultCoreName, "mGBA")
        XCTAssertEqual(SystemID.n64.defaultCoreName, "mupen64plus-next")
        XCTAssertEqual(SystemID.nds.defaultCoreName, "melonDS")
        XCTAssertEqual(SystemID.psp.defaultCoreName, "PPSSPP")
    }
}

import XCTest
@testable import RetroPlayCore

final class SavePathsTests: XCTestCase {
    func testSRAMAndStateURLsPreserveRelativeFolders() {
        let paths = SavePaths(fileManager: .default)
        let sram = paths.sramURL(forRelativeROMPath: "Pocket/demo.gba")
        XCTAssertEqual(sram.pathExtension, "sav")
        XCTAssertTrue(sram.path.contains("/Saves/"))
        XCTAssertTrue(sram.path.hasSuffix("Pocket/demo.sav"))

        let state = paths.stateURL(forRelativeROMPath: "demo.gba", slot: 2)
        XCTAssertTrue(state.path.contains("/States/"))
        XCTAssertEqual(state.lastPathComponent, "demo.slot2.state")
    }
}

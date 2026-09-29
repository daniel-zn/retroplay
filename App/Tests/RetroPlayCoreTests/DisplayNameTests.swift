// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class DisplayNameTests: XCTestCase {
    private func name(_ file: String) -> String {
        ROMImporter.displayName(fromFileName: file)
    }

    func testMovesTrailingArticleToFront() {
        XCTAssertEqual(name("Legend of Zelda, The - Ocarina of Time.z64"), "The Legend of Zelda - Ocarina of Time")
        XCTAssertEqual(name("Bug's Life, A.n64"), "A Bug's Life")
    }

    func testDropsDiscProductCode() {
        XCTAssertEqual(name("Crush ULUS10238.iso"), "Crush")
        XCTAssertEqual(name("ULUS-10238 Crush.iso"), "Crush")
        XCTAssertEqual(name("crush ulus10238.iso"), "crush")
    }

    func testDropsRegionAndDumpTags() {
        XCTAssertEqual(name("Pokemon - Emerald Version (USA, Europe).gba"), "Pokemon - Emerald Version")
        XCTAssertEqual(name("Mario Kart DS (USA) (Rev 1) [!].nds"), "Mario Kart DS")
    }

    func testLeavesCleanNamesAlone() {
        XCTAssertEqual(name("Super Mario Advance 4 - Super Mario Bros. 3.gba"), "Super Mario Advance 4 - Super Mario Bros. 3")
        XCTAssertEqual(name("Toy Story 3.nds"), "Toy Story 3")
        XCTAssertEqual(name("Theme Park, Deluxe.nds"), "Theme Park, Deluxe")
    }

    func testUnderscoresBecomeSpaces() {
        XCTAssertEqual(name("Metroid_Fusion.gba"), "Metroid Fusion")
    }

    func testFallsBackWhenOnlyTagsRemain() {
        XCTAssertEqual(name("(USA).gba"), "(USA)")
    }
}

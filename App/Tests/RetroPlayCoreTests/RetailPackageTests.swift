// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class RetailPackageTests: XCTestCase {
    func testEverySystemHasItsPackage() {
        for system in SystemID.allCases {
            let package = RetailPackage.of(system)
            XCTAssertFalse(package.frontBand.label.isEmpty, "\(system)")
            XCTAssertEqual(package.frontBand.label, package.spineBand.label, "\(system): front and spine name the same system")
            XCTAssertLessThanOrEqual(package.frontBand.label.count, 7, "\(system): the name fits a band")
            for band in [package.frontBand, package.spineBand] {
                XCTAssertGreaterThan(band.thickness, 0.05, "\(system)")
                XCTAssertLessThanOrEqual(band.thickness, 0.2, "\(system): the art keeps most of the face")
            }
            XCTAssertEqual(package.spineBand.edge, .top, "\(system): spines carry the name at the top")
        }
    }

    func testCartridgeSystemsComeInCardboardAndDiscsInCases() {
        for system in [SystemID.nes, .snes, .n64, .gba, .atari7800] {
            let package = RetailPackage.of(system)
            XCTAssertEqual(package.material, .cardboard, "\(system)")
            XCTAssertTrue(package.spineArt, "\(system): its art wraps onto the spine")
        }
        XCTAssertEqual(RetailPackage.of(.psp).material, .plasticCase)
        XCTAssertEqual(RetailPackage.of(.nds).material, .plasticCase)
        XCTAssertEqual(RetailPackage.of(.genesis).material, .plasticCase)
        XCTAssertEqual(RetailPackage.of(.ps1).material, .jewelCase)
        for system in [SystemID.psp, .nds, .genesis, .ps1] {
            XCTAssertFalse(RetailPackage.of(system).spineArt, "\(system): a printed insert, no wraparound art")
            XCTAssertNotNil(RetailPackage.of(system).spineColor, "\(system): the case's own colour")
        }
    }

    func testPackagesMatchTheBoxDepths() {
        // Cardboard boxes are the deep ones in Cover Flow, cases the thin ones.
        for system in SystemID.allCases where RetailPackage.of(system).material == .cardboard {
            for other in SystemID.allCases where RetailPackage.of(other).material != .cardboard && other != .genesis {
                XCTAssertGreaterThan(CoverFlow.boxDepth(system), CoverFlow.boxDepth(other), "\(system) vs \(other)")
            }
        }
    }

    func testRecognisablePackages() {
        // The parts that make each system's package read as itself.
        XCTAssertEqual(RetailPackage.of(.psp).frontBand.edge, .top)
        XCTAssertTrue(RetailPackage.of(.psp).frontBand.color.isDark, "PSP: black top band")
        XCTAssertFalse(RetailPackage.of(.nds).frontBand.color.isDark, "DS: white case")
        XCTAssertEqual(RetailPackage.of(.n64).frontBand.pattern, .colorBars)
        XCTAssertNotNil(RetailPackage.of(.n64).frontFrame, "N64: black frame")
        XCTAssertNotNil(RetailPackage.of(.nes).frontFrame, "NES: black box")
        XCTAssertEqual(RetailPackage.of(.genesis).frontBand.pattern, .gridLines)
        XCTAssertEqual(RetailPackage.of(.gba).frontBand.edge, .leading)
        XCTAssertEqual(RetailPackage.of(.ps1).frontBand.edge, .leading)
        XCTAssertEqual(RetailPackage.of(.snes).frontBand.edge, .bottom)
    }

    func testSpineTitlesReadOnTheirSpines() {
        // White on dark spines, dark on light ones; on art-coloured spines it follows the art.
        XCTAssertTrue(RetailPackage.of(.nes).spineTitleIsLight())
        XCTAssertFalse(RetailPackage.of(.psp).spineTitleIsLight())
        XCTAssertFalse(RetailPackage.of(.nds).spineTitleIsLight())
        let atari = RetailPackage.of(.atari7800)
        XCTAssertTrue(atari.spineTitleIsLight(edge: RetailPackage.RGB(0.2, 0.1, 0.1)))
        XCTAssertFalse(atari.spineTitleIsLight(edge: RetailPackage.RGB(0.95, 0.9, 0.7)))
        XCTAssertTrue(atari.spineTitleIsLight(), "no art: the dark system shade")
    }
}

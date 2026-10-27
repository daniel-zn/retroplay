// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Cover Flow taps: a tap anywhere on the middle cover plays it, never moving to a neighbour.
final class CoverFlowTapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTappingTheMiddleCoverDoesNotMoveTheRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-retroplay.libraryLayout", "coverFlow", "-RetroPlaySmokePortrait", "YES"]
        // Xcode points test launches at the build folder for frameworks, where the emulator
        // cores sit unsigned; the app's own signed copies are the ones to load.
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        let position = app.descendants(matching: .any)["coverFlow.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30), "no Cover Flow")
        sleep(2)
        let before = position.value as? String
        // The middle cover: the cover button centred on the screen.
        let middleX = app.windows.firstMatch.frame.midX
        let covers = app.buttons.allElementsBoundByIndex.filter { $0.label.contains(", ") && $0.frame.height > 100 }
        guard let middle = covers.min(by: { abs($0.frame.midX - middleX) < abs($1.frame.midX - middleX) }) else {
            return XCTFail("no covers")
        }
        // Its right part, where the next cover's layout slot lies under the row.
        let frame = middle.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX + frame.width * 0.3, dy: frame.midY))
            .tap()
        sleep(2)
        if position.exists {
            XCTAssertEqual(position.value as? String, before, "the tap moved the row to another game")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "cover-flow-after-tap"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

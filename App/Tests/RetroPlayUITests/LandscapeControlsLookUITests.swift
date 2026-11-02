// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Screenshots of the touch controls in landscape over a bright game and a darker one, in the
/// Liquid Glass and the flat style, at their fixed opacity. A screenshot set: run by the
/// on-request "screenshots" integration check.
final class LandscapeControlsLookUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLandscapeControlsOverBrightAndDarkGames() {
        XCUIDevice.shared.orientation = .landscapeLeft
        for system in ["gba", "nes"] {
            for flat in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-RetroPlaySmokeSystem", system, "-retroplay.flatControls", flat ? "YES" : "NO",
                                       // Shown although the Simulator's keyboard counts as a controller.
                                       "-retroplay.touchWithController", "YES"]
                app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
                app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
                app.launch()
                // Waits for the game (the pause button) rather than a fixed time, then a moment
                // for a picture behind the controls.
                XCTAssertTrue(app.buttons["Pause menu"].firstMatch.waitForExistence(timeout: 45), "\(system): no game")
                Thread.sleep(forTimeInterval: 3)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "controls-\(system)-\(flat ? "flat" : "glass")"
                shot.lifetime = .keepAlways
                add(shot)
                app.terminate()
            }
        }
    }
}

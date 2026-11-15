// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The App Store screenshots: the library (Cover Flow and grid), a game playing, its pause
/// menu and Settings, in the dark look at the default text size, portrait. Each attachment is
/// named after its file in docs/app-store/screenshots. `Scripts/app-store-screenshots.sh` runs
/// this with a library of free homebrew games only and the status bar at 9:41, and copies the
/// shots there; the on-request "screenshots" integration check runs it for review as well.
/// The titles' glitch is held off (`-RetroPlayTitleGlitchFrame -1`) so no shot catches a burst.
final class AppStoreScreenshotsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
                               "-retroplay.appearance", "dark", "-RetroPlayTitleGlitchFrame", "-1"] + extra
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        return app
    }

    @MainActor
    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "appstore-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@", label, label)).firstMatch
    }

    @MainActor
    func testLibrary() {
        for (layout, name) in [("coverFlow", "1-library"), ("grid", "2-library-grid")] {
            let app = launch(["-retroplay.libraryLayout", layout])
            XCTAssertTrue(text(app, "RetroPlay").waitForExistence(timeout: 30), "\(name): no title")
            XCTAssertTrue(app.buttons["library.settings"].firstMatch.waitForExistence(timeout: 10), "\(name): no top bar")
            Thread.sleep(forTimeInterval: 2)
            shoot(name)
            app.terminate()
        }
    }

    /// A game running (the smoke run presses Start, then A), then its pause menu. The touch
    /// controls stay on with a controller (the Simulator's keyboard counts as one).
    @MainActor
    func testPlayingAndPauseMenu() {
        // Breakout is the homebrew game that looks best mid-game (the Genesis and NES ones show a
        // debug readout and a "You died." screen).
        do {
            let app = launch(["-RetroPlaySmokeSystem", "snes", "-RetroPlaySmokeGame", "breakout", "-retroplay.touchWithController", "YES"])
            let start = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", "Start")).firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 45), "playing: no controls")
            Thread.sleep(forTimeInterval: 8)
            shoot("3-playing")
            app.terminate()
        }

        let app = launch(["-RetroPlaySmokeSystem", "snes", "-RetroPlaySmokeGame", "breakout", "-RetroPlaySmokeMenu", "YES",
                          "-retroplay.touchWithController", "YES"])
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Resume")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 45), "pause menu: no Resume")
        Thread.sleep(forTimeInterval: 1.5)
        shoot("4-pause-menu")
        app.terminate()
    }

    @MainActor
    func testSettings() {
        let app = launch(["-retroplay.libraryLayout", "coverFlow", "-RetroPlaySmokeSettings", "YES"])
        XCTAssertTrue(text(app, "Settings").waitForExistence(timeout: 30), "settings: no title")
        Thread.sleep(forTimeInterval: 1.5)
        shoot("5-settings")
        app.terminate()
    }
}

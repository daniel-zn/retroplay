// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The main screens in the app's type, for review: dark and light at the default text size,
/// and dark at the larger sizes players use (XXXL and an accessibility size). Each screen
/// checks its key text is on screen and inside it; the screenshots are attached. Run by the
/// on-request "screenshots" integration check (type, theme and layout changes name it).
final class TypographyScreenshotsUITests: XCTestCase {
    private let looks: [(name: String, appearance: String, size: String)] = [
        ("dark", "dark", "UICTContentSizeCategoryL"),
        ("light", "light", "UICTContentSizeCategoryL"),
        ("dark-xxxl", "dark", "UICTContentSizeCategoryXXXL"),
        ("dark-ax2", "dark", "UICTContentSizeCategoryAccessibilityL"),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(_ look: (name: String, appearance: String, size: String), _ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", look.size, "-retroplay.appearance", look.appearance] + extra
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        return app
    }

    @MainActor
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "type-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A text that must be on screen, whole and inside the window.
    @MainActor
    private func expectVisible(_ app: XCUIApplication, _ label: String, _ context: String, timeout: TimeInterval = 20) {
        let text = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@", label, label)).firstMatch
        guard text.waitForExistence(timeout: timeout) else {
            XCTFail("\(context): no “\(label)”")
            return
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(text.frame) || window.intersects(text.frame), "\(context): “\(label)” is off screen: \(text.frame)")
    }

    @MainActor
    func testLibraryGridAndCoverFlow() {
        for look in looks {
            let grid = launch(look, ["-retroplay.libraryLayout", "grid"])
            expectVisible(grid, "RetroPlay", "grid \(look.name)", timeout: 30)
            Thread.sleep(forTimeInterval: 1)
            shoot(grid, "library-grid-\(look.name)")
            grid.terminate()

            let flow = launch(look, ["-retroplay.libraryLayout", "coverFlow"])
            expectVisible(flow, "RetroPlay", "cover flow \(look.name)", timeout: 30)
            Thread.sleep(forTimeInterval: 2)
            shoot(flow, "library-coverflow-\(look.name)")
            flow.terminate()
        }
    }

    /// Settings, then (swiped closed) search, in one launch per look.
    @MainActor
    func testSearchAndSettings() {
        for look in looks {
            let app = launch(look, ["-retroplay.libraryLayout", "grid", "-RetroPlaySmokeSettings", "YES"])
            expectVisible(app, "Settings", "settings \(look.name)", timeout: 30)
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "settings-\(look.name)")
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "settings-scrolled-\(look.name)")
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085))
                .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@", "Settings")).firstMatch.waitForNonExistence(timeout: 10), "settings \(look.name): didn't close")

            let search = app.buttons["library.search"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            Thread.sleep(forTimeInterval: 1.5)
            app.typeText("Su")
            Thread.sleep(forTimeInterval: 1)
            shoot(app, "search-\(look.name)")
            app.terminate()
        }
    }

    @MainActor
    func testSaveImportSummaryAndPlayMenu() {
        for look in looks {
            let sheet = launch(look, ["-RetroPlaySmokeSaveImport", "YES"])
            expectVisible(sheet, "Found 4 saves", "save import \(look.name)", timeout: 30)
            Thread.sleep(forTimeInterval: 1)
            shoot(sheet, "save-import-\(look.name)")
            sheet.terminate()

            // A game's pause menu (opened by the smoke argument once the game runs).
            let play = launch(look, ["-RetroPlaySmokeSystem", "nes", "-RetroPlaySmokeMenu", "YES"])
            let resume = play.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Resume")).firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 45), "play menu \(look.name): no Resume")
            Thread.sleep(forTimeInterval: 1)
            shoot(play, "play-menu-\(look.name)")
            play.terminate()
        }
    }
}

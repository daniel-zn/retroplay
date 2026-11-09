// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The main screens in the app's type, for review: dark and light at the default text size,
/// and dark at the larger sizes players use (XXXL and an accessibility size). Each screen
/// checks its key text is on screen and inside it; the screenshots are attached. Run by the
/// on-request "screenshots" integration check (type, theme and layout changes name it).
/// The titles' glitch is off in these (`-RetroPlayTitleGlitchFrame -1`) so the screens are
/// steady, except in `testTitleGlitchFrames`, which shows each frame of a burst held still.
final class TypographyScreenshotsUITests: XCTestCase {
    private let looks: [(name: String, appearance: String, size: String)] = [
        ("dark", "dark", "UICTContentSizeCategoryL"),
        ("light", "light", "UICTContentSizeCategoryL"),
        ("dark-xxxl", "dark", "UICTContentSizeCategoryXXXL"),
        ("dark-ax2", "dark", "UICTContentSizeCategoryAccessibilityL"),
    ]

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch(_ look: (name: String, appearance: String, size: String), _ extra: [String], glitchFrame: Int = -1) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", look.size, "-retroplay.appearance", look.appearance,
                               "-RetroPlayTitleGlitchFrame", String(glitchFrame)] + extra
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        return app
    }

    @MainActor
    private func shoot(_ app: XCUIApplication, _ name: String) {
        // The screen, not the app: in landscape app.screenshot() comes out rotated twice.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    /// Cover Flow in landscape, and the library while saves are found (the status in the
    /// bottom bar).
    @MainActor
    func testLibraryLandscapeAndImporting() {
        for look in looks {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = launch(look, ["-retroplay.libraryLayout", "coverFlow"])
            XCTAssertTrue(landscape.buttons["library.settings"].firstMatch.waitForExistence(timeout: 30), "landscape \(look.name): no top bar")
            Thread.sleep(forTimeInterval: 2)
            shoot(landscape, "library-landscape-\(look.name)")
            landscape.terminate()
            XCUIDevice.shared.orientation = .portrait

            let importing = launch(look, ["-retroplay.libraryLayout", "coverFlow", "-RetroPlaySmokeSaveScan", "YES"])
            XCTAssertTrue(importing.descendants(matching: .any)["library.findingSaves"].firstMatch.waitForExistence(timeout: 30), "importing \(look.name): no status")
            Thread.sleep(forTimeInterval: 1)
            shoot(importing, "library-importing-\(look.name)")
            importing.terminate()
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

    /// Saves Waiting for Games with none waiting: its empty state's title in the italic, a
    /// burst's first and a later frame held still (dark and light).
    @MainActor
    func testWaitingSavesEmptyTitleGlitch() {
        for look in looks.prefix(2) {
            for frame in [0, 3] {
                let app = launch(look, ["-retroplay.libraryLayout", "grid", "-RetroPlaySmokeSettings", "YES"], glitchFrame: frame)
                // Settings is a lazy List: the row exists only once it's scrolled into view.
                let settings = app.collectionViews.firstMatch
                XCTAssertTrue(settings.waitForExistence(timeout: 30), "waiting saves \(look.name): Settings didn't open")
                let row = app.buttons["settings.keptSaves"].firstMatch
                for _ in 0..<8 where !(row.exists && row.isHittable) { settings.swipeUp() }
                XCTAssertTrue(row.waitForExistence(timeout: 5), "waiting saves \(look.name): no row")
                row.tap()
                expectVisible(app, "No Waiting Saves", "waiting saves \(look.name)", timeout: 10)
                Thread.sleep(forTimeInterval: 1)
                shoot(app, "glitch-waiting-saves-empty-\(look.name)-frame\(frame)")
                app.terminate()
            }
        }
    }

    /// The titles' glitch, each frame of a burst held still (dark and light): the large title
    /// and the section headings hacked in lime and violet, still read as themselves (VoiceOver
    /// and the tests see the plain title throughout).
    @MainActor
    func testTitleGlitchFrames() {
        for look in looks.prefix(2) {
            for frame in 0..<6 {
                let app = launch(look, ["-retroplay.libraryLayout", "grid"], glitchFrame: frame)
                expectVisible(app, "RetroPlay", "glitch frame \(frame) \(look.name)", timeout: 30)
                Thread.sleep(forTimeInterval: 1)
                shoot(app, "glitch-\(look.name)-frame\(frame)")
                app.terminate()
            }
        }
    }
}

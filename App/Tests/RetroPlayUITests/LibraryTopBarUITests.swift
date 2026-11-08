// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The library's top-right buttons: the system's own toolbar items, in order in one row at the
/// top, at the default text size and at a large one; and the bar
/// keeps its width while saves import (the status is in the bottom bar).
final class LibraryTopBarUITests: XCTestCase {
    private let ids = ["library.import", "library.filter", "library.search", "library.settings"]

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// The four buttons, once laid out and touchable (the bar settles after launch).
    @MainActor
    private func topBar(_ app: XCUIApplication, _ context: String) -> [XCUIElement] {
        // In the navigation bar itself: bar items, not views drawn over it.
        let buttons = ids.map { app.navigationBars.buttons[$0].firstMatch }
        for (id, button) in zip(ids, buttons) {
            XCTAssertTrue(button.waitForExistence(timeout: 30), "\(context): no \(id) in the navigation bar")
        }
        let settled = buttons.map {
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: $0)
        }
        XCTAssertEqual(XCTWaiter().wait(for: settled, timeout: 10), .completed, "\(context): buttons not hittable")
        return buttons
    }

    /// The bar's span, from the first button's leading edge to the last one's trailing edge.
    @MainActor
    private func span(_ buttons: [XCUIElement]) -> CGRect {
        buttons.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }

    @MainActor
    func testTopBarIsOneRowOfSystemItems() {
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL"] {
            let app = launch(["-UIPreferredContentSizeCategoryName", size])
            let frames = topBar(app, size).map(\.frame)
            let steps = zip(frames.dropFirst(), frames).map { $0.midX - $1.midX }
            print("[top-bar] \(size): \(frames), centres \(steps) pt apart")
            for step in steps {
                XCTAssertGreaterThan(step, 0, "\(size): the buttons are out of order: \(steps)")
            }
            let window = app.windows.firstMatch.frame
            for (id, frame) in zip(ids, frames) {
                // The bar reports the symbol's frame; its touch area is the system's own.
                XCTAssertGreaterThanOrEqual(frame.width, 24, "\(size): \(id) is \(frame.size)")
                XCTAssertEqual(frame.midY, frames[0].midY, accuracy: 2, "\(size): \(id) isn't in the row")
                XCTAssertLessThan(frame.maxY, 140, "\(size): \(id) isn't at the top")
            }
            // Trailing: the system grows its items with Dynamic Type, so at XXXL the group of four
            // reaches past the centre; it still ends at the bar's trailing edge.
            XCTAssertLessThan(window.maxX - frames[frames.count - 1].maxX, 40, "\(size): the bar isn't on the trailing edge")
            XCTAssertGreaterThan(frames[0].minX, window.width * 0.35, "\(size): the bar reaches into the title")
            attach(app, "top-bar-\(size)")
            app.terminate()
        }
    }

    /// While saves are found the top bar keeps its four buttons and its width; the status and
    /// Stop are in the bottom bar, and Stop ends the scan. Portrait and landscape.
    @MainActor
    func testTopBarKeepsItsWidthWhileSavesImport() {
        for orientation in ["portrait", "landscape"] {
            XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
            let app = launch(["-RetroPlaySmokeSaveScan", "YES"])
            let status = app.descendants(matching: .any)["library.findingSaves"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 30), "\(orientation): no import status")
            let during = topBar(app, "\(orientation) importing")
            let importing = span(during)
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThan(status.frame.midY, window.midY, "\(orientation): the status isn't at the bottom: \(status.frame)")
            XCTAssertFalse(during[0].isEnabled, "\(orientation): + takes a second import while saves are found")
            XCTAssertFalse(app.navigationBars.descendants(matching: .any)["library.findingSaves"].exists, "\(orientation): the status is in the top bar")
            attach(app, "mid-import-\(orientation)")

            let stop = app.buttons["library.stopFindingSaves"].firstMatch
            XCTAssertTrue(stop.waitForExistence(timeout: 5) && stop.isHittable, "\(orientation): Stop can't be reached")
            stop.tap()
            XCTAssertTrue(status.waitForNonExistence(timeout: 10), "\(orientation): Stop didn't end the scan")
            let after = topBar(app, "\(orientation) after")
            let idle = span(after)
            XCTAssertTrue(after[0].isEnabled, "\(orientation): + stays off after the scan stopped")
            print("[top-bar] \(orientation): importing \(importing), idle \(idle)")
            XCTAssertEqual(importing.width, idle.width, accuracy: 0.5, "\(orientation): the bar's width changed while importing")
            XCTAssertEqual(importing.minX, idle.minX, accuracy: 0.5, "\(orientation): the bar moved while importing")
            attach(app, "library-\(orientation)")
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        // The screen, not the app: in landscape app.screenshot() comes out rotated twice.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Menus iOS draws itself keep its look: normal case and the system font (the "+" menu,
    /// and a game's long-press menu).
    @MainActor
    func testSystemMenusKeepTheirOwnCase() {
        let app = launch(["-retroplay.libraryLayout", "grid"])
        let plus = app.buttons["library.import"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 30))
        plus.tap()
        let games = app.buttons["library.import.games"].firstMatch
        let saves = app.buttons["library.import.saves"].firstMatch
        XCTAssertTrue(games.waitForExistence(timeout: 5), "no Games in the + menu")
        // Case-sensitive on purpose.
        XCTAssertTrue(games.label.hasPrefix("Games"), "the + menu says “\(games.label)”")
        XCTAssertTrue(saves.label.hasPrefix("Saves"), "the + menu says “\(saves.label)”")
        attach(app, "plus-menu-case")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()

        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", ", ")).element(boundBy: 0)
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no game in the grid")
        tile.press(forDuration: 1.2)
        let play = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Play", "Continue")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5), "the game's menu has no “Play” / “Continue” in normal case")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch.exists, "no “Delete” in normal case")
        attach(app, "context-menu-case")
        app.terminate()
    }

    /// Settings is a swipe-down sheet: no Done button, and a swipe down from its top closes it.
    @MainActor
    func testSettingsHasNoDoneButtonAndSwipesClosed() {
        let app = launch(["-RetroPlaySmokeSettings", "YES"])
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@", "Settings")).firstMatch.waitForExistence(timeout: 30), "no Settings")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Done")).firstMatch.exists, "Settings has a Done button")
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@", "Settings")).firstMatch.waitForNonExistence(timeout: 10), "a swipe down didn't close Settings")
        app.terminate()
    }

    /// "+" opens a menu with Games and Saves (like the filter's), at the default size and a
    /// large one, in dark and light.
    @MainActor
    func testImportButtonOffersGamesAndSaves() {
        for (size, appearance) in [("UICTContentSizeCategoryL", "dark"), ("UICTContentSizeCategoryAccessibilityL", "light")] {
            let app = launch(["-UIPreferredContentSizeCategoryName", size, "-retroplay.appearance", appearance])
            let plus = app.buttons["library.import"].firstMatch
            XCTAssertTrue(plus.waitForExistence(timeout: 30), "\(size): no + button")
            plus.tap()
            // Menu rows carry their subtitle in the label ("Games, ROMs and discs").
            func item(_ id: String, _ title: String) -> XCUIElement {
                app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH[c] %@", id, title)).firstMatch
            }
            let games = item("library.import.games", "Games")
            let saves = item("library.import.saves", "Saves")
            XCTAssertTrue(games.waitForExistence(timeout: 5), "\(size): no Games in the menu")
            XCTAssertTrue(saves.exists, "\(size): no Saves in the menu")
            XCTAssertLessThan(games.frame.midY, saves.frame.midY, "\(size): Games should come first")
            attach(app, "import-menu-\(appearance)-\(size)")
            app.terminate()
        }
    }

    /// Saves opens the Files picker for a folder (iOS's picker only selects folders when
    /// nothing else is allowed): it shows Open with nothing selected (enabled once a folder,
    /// not Recents, is showing).
    @MainActor
    func testSavesOpensAFolderPicker() throws {
        let app = launch([])
        let plus = app.buttons["library.import"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 30))
        plus.tap()
        let saves = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH[c] %@", "library.import.saves", "Saves")).firstMatch
        XCTAssertTrue(saves.waitForExistence(timeout: 5))
        saves.tap()
        let open = app.buttons["Open"].firstMatch
        // The picker draws out of process; on a cold Simulator its sheet can stay blank for
        // well over 20 s.
        let found = open.waitForExistence(timeout: 60)
        attach(app, "save-folder-picker")
        XCTAssertTrue(found, "no Open button: the picker isn't in folder mode")
        app.terminate()
    }

    /// The save import summary (sample rows from a debug launch argument): counts, sections,
    /// and both choices when a save would be replaced.
    @MainActor
    func testSaveImportSummarySheet() {
        for (size, appearance) in [
            ("UICTContentSizeCategoryL", "dark"),
            ("UICTContentSizeCategoryL", "light"),
            ("UICTContentSizeCategoryAccessibilityL", "dark"),
        ] {
            let app = launch([
                "-UIPreferredContentSizeCategoryName", size,
                "-retroplay.appearance", appearance,
                "-RetroPlaySmokeSaveImport", "YES",
            ])
            let summary = app.staticTexts["saveImport.summary"].firstMatch
            XCTAssertTrue(summary.waitForExistence(timeout: 30), "\(size): no summary sheet")
            XCTAssertEqual(summary.label.lowercased(), "found 4 saves for 4 games. 1 for games not in your library yet. 2 skipped.")
            // An N64 game's loose saves say what they add; a PSP save for a game not in the
            // library has its own section, named by product ID.
            func shows(_ text: String) -> Bool {
                app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch.exists
            }
            XCTAssertTrue(shows("Adds EEPROM, Controller Pak 1"), "\(size): the N64 row doesn't say what it adds")
            app.swipeUp()
            XCTAssertTrue(shows("For games not in your library yet"), "\(size): no section for games not in the library")
            XCTAssertTrue(shows("Product ID ULUS10041"), "\(size): the save for a game not in the library isn't listed")
            app.swipeDown()
            XCTAssertTrue(app.buttons["saveImport.import"].exists)
            XCTAssertTrue(app.buttons["saveImport.keepExisting"].exists)
            attach(app, "save-import-\(appearance)-\(size)")
            app.terminate()
        }
    }

    /// A folder whose save sits three folders down is walked through the app's own import path
    /// (security scope, coordinated read, scan off the main actor): its summary lists the save.
    @MainActor
    func testPickedFolderWithANestedSaveIsWalked() {
        let app = launch(["-RetroPlaySmokeSaveFolder", "YES"])
        let summary = app.staticTexts["saveImport.summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "no summary: the walk found nothing")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "SmokeSaves/A/B/C/Zelda.sav"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the nested save isn't listed")
        attach(app, "save-import-nested-folder")
        app.terminate()
    }
}

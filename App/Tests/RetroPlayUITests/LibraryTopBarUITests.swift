// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The library's top-right buttons: in order, close together in one capsule, each still a full
/// touch target, at the default text size and at a large one.
final class LibraryTopBarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTopBarButtonsSitCloseTogether() {
        let ids = ["library.import", "library.filter", "library.search", "library.settings"]
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", size]
            // Xcode points test launches at the build folder for frameworks, where the
            // emulator cores sit unsigned; the app's own signed copies are the ones to load.
            app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
            app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
            app.launch()
            let buttons = ids.map { app.buttons[$0].firstMatch }
            for (id, button) in zip(ids, buttons) {
                XCTAssertTrue(button.waitForExistence(timeout: 30), "\(size): no \(id)")
            }
            // Laid out and touchable (the bar settles after launch), not a fixed wait.
            let settled = buttons.map {
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: $0)
            }
            XCTAssertEqual(XCTWaiter().wait(for: settled, timeout: 10), .completed, "\(size): buttons not hittable")
            let frames = buttons.map { $0.frame }
            // Icon centres no more than 48 pt apart (a toolbar group, or icons built as labels,
            // put 55-66 pt between them), each at least 44 pt wide to touch.
            let steps = zip(frames.dropFirst(), frames).map { $0.midX - $1.midX }
            print("[top-bar] \(size): \(frames), centres \(steps) pt apart")
            for step in steps {
                XCTAssertGreaterThan(step, 0, "\(size): the buttons are out of order: \(steps)")
                XCTAssertLessThanOrEqual(step, 48, "\(size): the icons are \(steps) pt apart")
            }
            for (id, frame) in zip(ids, frames) {
                XCTAssertGreaterThanOrEqual(frame.width, 44, "\(size): \(id) is \(frame.size), under 44 pt wide")
                XCTAssertEqual(frame.midY, frames[0].midY, accuracy: 2, "\(size): \(id) isn't in the row")
                XCTAssertLessThan(frame.maxY, 140, "\(size): \(id) isn't at the top")
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "top-bar-\(size)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
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
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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
                app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", id, title)).firstMatch
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
            XCTAssertEqual(summary.label, "Found 4 saves for 4 games. 2 skipped.")
            XCTAssertTrue(app.buttons["saveImport.import"].exists)
            XCTAssertTrue(app.buttons["saveImport.keepExisting"].exists)
            attach(app, "save-import-\(appearance)-\(size)")
            app.terminate()
        }
    }
}

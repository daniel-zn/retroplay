// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Search lives in the library itself, as iOS's own search field under the large title: hidden
/// until the library is pulled down (in the grid and in Cover Flow, whose covers sit in a page
/// that pulls down the same way), and Command-F brings it up from a hardware keyboard.
final class LibraryPullToSearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-RetroPlayTitleGlitchFrame", "-1"]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitFor(_ format: String, _ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The library, laid out: its top bar is there and a game shows. Returns a query that
    /// finds that game (the start of its name), so the test doesn't lean on which games exist.
    @MainActor
    @discardableResult
    private func waitForLibrary(_ app: XCUIApplication, _ context: String) -> String {
        let settings = app.navigationBars.buttons["library.settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "\(context): no library")
        let game = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", ")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 20), "\(context): no game shows")
        XCTAssertTrue(waitFor("isHittable == true", settings, timeout: 10), "\(context): the bar didn't settle")
        return String(game.label.prefix(3))
    }

    /// The search field, not on screen yet: there is no Search button any more, only the pull.
    @MainActor
    private func expectSearchHidden(_ app: XCUIApplication, _ context: String) {
        XCTAssertFalse(app.buttons["library.search"].exists, "\(context): a Search button is still in the bar")
        let field = app.searchFields.firstMatch
        XCTAssertFalse(field.exists && field.isHittable && field.frame.height > 20,
                       "\(context): the search field shows before the library was pulled down: \(field.frame)")
    }

    /// A pull down from `from` (normalised, in the window), slow enough to be a drag.
    @MainActor
    private func pullDown(_ app: XCUIApplication, from y: CGFloat) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            .press(forDuration: 0.05,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y + 0.3)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    /// The pull left the search field on screen, and typing in it shows the matching games.
    @MainActor
    private func expectSearchWorks(_ app: XCUIApplication, _ context: String, query: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5) && waitFor("isHittable == true", field, timeout: 5),
                      "\(context): pulling down didn't show the search field")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(field.frame.maxY, window.height * 0.4, "\(context): the search field isn't at the top: \(field.frame)")
        attach("pull-search-\(context)-revealed")
        field.tap()
        app.typeText(query)
        let results = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@ OR label ENDSWITH[c] %@", "Result", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10), "\(context): typing didn't show results")
        attach("pull-search-\(context)-results")
    }

    @MainActor
    func testPullingTheGridDownRevealsSearch() {
        let app = launch(["-retroplay.libraryLayout", "grid"])
        let query = waitForLibrary(app, "grid")
        expectSearchHidden(app, "grid")
        pullDown(app, from: 0.35)
        expectSearchWorks(app, "grid", query: query)
        app.terminate()
    }

    /// The same pull on Cover Flow, started on the covers themselves (they only swipe sideways).
    @MainActor
    func testPullingCoverFlowDownRevealsSearch() {
        let app = launch(["-retroplay.libraryLayout", "coverFlow"])
        let query = waitForLibrary(app, "coverflow")
        let position = app.descendants(matching: .any)["coverFlow.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10), "no Cover Flow")
        expectSearchHidden(app, "coverflow")
        let before = position.value as? String
        pullDown(app, from: 0.4)
        XCTAssertEqual(position.value as? String, before, "the pull down moved the covers sideways")
        expectSearchWorks(app, "coverflow", query: query)
        app.terminate()
    }

    /// Command-F on a hardware keyboard puts the cursor in the search field, in both layouts.
    @MainActor
    func testCommandFSearchesTheGrid() { expectCommandFSearches("grid") }

    @MainActor
    func testCommandFSearchesCoverFlow() { expectCommandFSearches("coverFlow") }

    @MainActor
    private func expectCommandFSearches(_ layout: String) {
        let app = launch(["-retroplay.libraryLayout", layout])
        let query = waitForLibrary(app, layout)
        let field = app.searchFields.firstMatch
        // The Simulator can drop the first key event after a launch (it connects its hardware
        // keyboard then), so up to three presses; the count is logged.
        var focused = false
        for press in 1...3 where !focused {
            app.typeKey("f", modifierFlags: .command)
            focused = waitFor("hasKeyboardFocus == true", field, timeout: 4)
            print("[command-f] \(layout) press \(press): field \(field.exists) focused \(focused)")
        }
        attach("command-f-\(layout)")
        XCTAssertTrue(focused, "\(layout): Command-F didn't put the cursor in the search field")
        app.typeText(query)
        let results = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@ OR label ENDSWITH[c] %@", "Result", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10), "\(layout): typing after Command-F didn't search")
        app.terminate()
    }
}

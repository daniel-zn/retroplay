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

    private func launch(_ arguments: [String], glitchTitle: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + (glitchTitle ? [] : ["-RetroPlayTitleGlitchFrame", "-1"])
        app.launchRetroPlay()
        return app
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
        attachScreen("pull-search-\(context)-revealed")
        field.tap()
        app.typeText(query)
        let results = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@ OR label ENDSWITH[c] %@", "Result", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10), "\(context): typing didn't show results")
        attachScreen("pull-search-\(context)-results")
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

    /// Cover Flow has nothing to scroll up to: a hard push up leaves the big title big (it
    /// used to collapse into the bar's inline title and stay there). A pull down still shows
    /// search, and a push up then hides it, back to the page at rest with the big title.
    @MainActor
    func testCoverFlowPushUpKeepsTheBigTitle() {
        let app = launch(["-retroplay.libraryLayout", "coverFlow"])
        waitForLibrary(app, "coverflow")
        XCTAssertTrue(app.descendants(matching: .any)["coverFlow.position"].waitForExistence(timeout: 10), "no Cover Flow")
        let window = app.windows.firstMatch
        let field = app.searchFields.firstMatch
        func drag(_ from: CGFloat, _ to: CGFloat, _ velocity: XCUIGestureVelocity) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.05,
                       thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                       withVelocity: velocity, thenHoldForDuration: 0.05)
        }
        func searchShows() -> Bool { field.exists && field.isHittable && field.frame.height > 20 }
        expectBigTitle(app, "at rest")
        for (index, velocity) in [XCUIGestureVelocity.fast, .slow, .fast].enumerated() {
            drag(0.75, 0.1, velocity)
            Thread.sleep(forTimeInterval: 1.5)
            expectBigTitle(app, "push up \(index + 1)")
        }
        attachScreen("coverflow-after-push-up")
        drag(0.4, 0.75, .slow)
        waitUntilStill(field)
        XCTAssertTrue(searchShows(), "the pull down didn't show search")
        drag(0.75, 0.1, .fast)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(searchShows(), "the push up didn't hide search")
        expectBigTitle(app, "push up from search")
        app.terminate()
    }

    /// The big title shows, below the bar's buttons (the inline title sits beside them).
    @MainActor
    private func expectBigTitle(_ app: XCUIApplication, _ context: String) {
        let titles = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "RetroPlay"))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 0 }
        let buttons = app.navigationBars.buttons["library.settings"].firstMatch.frame
        print("[push-up] \(context): titles \(titles.map { $0.frame }) buttons \(buttons)")
        let big = titles.filter { $0.frame.height >= 40 && $0.frame.minY >= buttons.maxY - 2 && $0.isHittable }
        XCTAssertFalse(big.isEmpty, "\(context): the big title collapsed: \(titles.map { $0.frame })")
    }

    /// What showing and hiding the search field costs, in the grid and in Cover Flow (with the
    /// plain title and the glitching one): late frames (the main thread busy past a refresh) and
    /// how often the library's views were evaluated again, over slow and fast pulls down (the
    /// field shows) and back up (it hides). Debug builds count these (`LibraryWorkProbe`).
    @MainActor
    func testPullDownWork() {
        for (name, layout, glitch) in [("grid", "grid", false), ("coverFlow", "coverFlow", false),
                                       ("coverFlow-glitch", "coverFlow", true)] {
            // Box art the size real covers are stored at, on every game.
            let app = launch(["-retroplay.libraryLayout", layout, "-RetroPlayTestBoxArt", "YES"], glitchTitle: glitch)
            waitForLibrary(app, layout)
            let work = app.descendants(matching: .any)["library.work"]
            XCTAssertTrue(work.waitForExistence(timeout: 10), "\(name): no work probe")
            Thread.sleep(forTimeInterval: 3)
            let before = Self.numbers(work.value as? String)
            let window = app.windows.firstMatch
            let field = app.searchFields.firstMatch
            func drag(_ from: CGFloat, _ to: CGFloat, _ velocity: XCUIGestureVelocity) {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                    .press(forDuration: 0.05,
                           thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                           withVelocity: velocity, thenHoldForDuration: 0.1)
            }
            var shown = 0, hidden = 0
            for velocity in [XCUIGestureVelocity.slow, .slow, .fast, .fast] {
                drag(0.4, 0.75, velocity)
                waitUntilStill(field)
                if field.exists && field.isHittable && field.frame.height > 20 { shown += 1 }
                drag(0.75, 0.3, velocity)
                waitUntilStill(field)
                if !(field.exists && field.isHittable && field.frame.height > 20) { hidden += 1 }
            }
            Thread.sleep(forTimeInterval: 1)
            let after = Self.numbers(work.value as? String)
            let delta = after.keys.sorted().map { "\($0)=\((after[$0] ?? 0) - (before[$0] ?? 0))" }.joined(separator: " ")
            print("[pull-work] \(name): shown \(shown)/4 hidden \(hidden)/4 \(delta)")
            XCTAssertFalse(after.isEmpty, "\(name): the probe read nothing")
            XCTAssertGreaterThanOrEqual(shown, 3, "\(name): the pulls down didn't show the search field")
            // The grid scrolls on under a pull up (the field may stay); Cover Flow's page fits.
            if layout == "coverFlow" {
                XCTAssertGreaterThanOrEqual(hidden, 3, "\(name): the pulls up didn't hide the search field")
            }
            func count(_ key: String) -> Int { (after[key] ?? 0) - (before[key] ?? 0) }
            // Before: the page followed the bar, so every frame of the field showing or hiding
            // laid Cover Flow's page out again (216 to 267 times over these pulls), and with
            // the glitching title the room left made the covers smaller, building the row and
            // its covers again mid-pull. The page now keeps its size while it's pulled.
            XCTAssertEqual(count("pagePasses"), 0, "\(name): showing and hiding search laid the Cover Flow page out \(count("pagePasses")) times")
            XCTAssertEqual(count("carousel"), 0, "\(name): showing and hiding search built the row of covers \(count("carousel")) times")
            XCTAssertLessThanOrEqual(count("coverFlow"), 3, "\(name): the pulls ran the Cover Flow view \(count("coverFlow")) times")
            XCTAssertEqual(count("gapSearches"), 0, "\(name): the pulls searched the Cover Flow gaps \(count("gapSearches")) times")
            app.terminate()
        }
    }

    private static func numbers(_ value: String?) -> [String: Int] {
        var result: [String: Int] = [:]
        for pair in (value ?? "").split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let n = Int(parts[1]) { result[String(parts[0])] = n }
        }
        return result
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
        attachScreen("command-f-\(layout)")
        XCTAssertTrue(focused, "\(layout): Command-F didn't put the cursor in the search field")
        app.typeText(query)
        let results = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@ OR label ENDSWITH[c] %@", "Result", "Results")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 10), "\(layout): typing after Command-F didn't search")
        app.terminate()
    }
}

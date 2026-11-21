// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// A game import (`-RetroPlayTestImportSeconds`: a 16 MB file from tmp, copied slowly): it
/// shows as a fourth button at the start of the top bar's group (no bottom bar status), whose
/// popover lists the copy with its progress and a cancel; it keeps copying when the app goes
/// to the background (the app isn't suspended mid-copy); and the library's subtitle keeps its
/// font while the bar changes.
final class LibraryImportUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launch(importSeconds: Double? = nil, _ more: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-retroplay.libraryLayout", "grid",
            // The bar's own title, so its subtitle is in the accessibility tree.
            "-RetroPlayTitleGlitchFrame", "-1",
        ] + (importSeconds.map { ["-RetroPlayTestImportSeconds", "\($0)"] } ?? []) + more
        app.launchRetroPlay()
        return app
    }

    /// The bar's title and game count, measured (their fonts set their widths).
    @MainActor
    private func titleFrames(_ app: XCUIApplication, _ context: String) -> (title: CGRect, subtitle: CGRect, label: String) {
        let title = app.navigationBars.staticTexts["RetroPlay"].firstMatch
        let count = subtitle(app)
        XCTAssertTrue(title.waitForExistence(timeout: 30), "\(context): no title")
        XCTAssertTrue(count.waitForExistence(timeout: 10), "\(context): no game count under the title")
        waitUntilStill(count)
        print("[import] \(context): title \(title.frame), subtitle “\(count.label)” \(count.frame)")
        return (title.frame, count.frame, count.label)
    }

    private func importButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons["library.imports"].firstMatch
    }

    private func importedTile(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Import Test")).firstMatch
    }

    /// The game count under the title ("8 games", "GBA · 2 of 9 games").
    private func subtitle(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@", " games")).firstMatch
    }

    /// The import's button joins the top bar's group on its leading side while the copy runs,
    /// with no status in the bottom bar; its popover shows the copy's progress; the button
    /// goes when the game is in; the subtitle keeps its font throughout.
    @MainActor
    func testImportShowsInTheTopBarGroup() {
        let app = launch(importSeconds: 12)
        let button = importButton(app)
        let found = button.waitForExistence(timeout: 30)
        attachScreen("import-topbar")
        XCTAssertFalse(app.descendants(matching: .any)["library.importingGames"].exists, "the bottom bar's import pill is still there")
        XCTAssertTrue(found, "no import button in the top bar while a game imports")
        let plus = app.navigationBars.buttons["library.import"].firstMatch
        XCTAssertTrue(plus.exists)
        XCTAssertLessThan(button.frame.maxX, plus.frame.minX + 1, "the import button isn't before +: \(button.frame) vs \(plus.frame)")
        XCTAssertEqual(button.frame.midY, plus.frame.midY, accuracy: 2, "the import button isn't in the row")

        button.tap()
        let row = app.descendants(matching: .any)["library.imports.item"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "tapping the button shows no import status")
        XCTAssertTrue(row.label.localizedCaseInsensitiveContains("Import Test"), "the status says “\(row.label)”")
        XCTAssertTrue(app.descendants(matching: .any)["library.imports.progress"].firstMatch.exists, "no progress in the status")
        attachScreen("import-status")
        // Out of the popover (a tap outside closes it).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()

        XCTAssertTrue(button.waitForNonExistence(timeout: 40), "the import button stays after the import")
        XCTAssertTrue(importedTile(app).waitForExistence(timeout: 10), "the imported game isn't in the library")
        Thread.sleep(forTimeInterval: 1)
        let after = titleFrames(app, "after the import")
        attachScreen("import-done")
        app.terminate()

        // The same library, launched fresh: the title and count in the RetroPlay font. After
        // the import (the count changed, the button came and went) they must still match.
        let fresh = launch()
        let launched = titleFrames(fresh, "fresh launch")
        XCTAssertEqual(after.title.width, launched.title.width, accuracy: 1, "the title lost its font after the import")
        // The import switched the filter to its system, so the count reads differently; per
        // character, the RetroPlay font's capitals run far wider than the system font's lower case.
        func perCharacter(_ frames: (title: CGRect, subtitle: CGRect, label: String)) -> CGFloat {
            frames.subtitle.width / CGFloat(max(frames.label.count, 1))
        }
        XCTAssertEqual(perCharacter(after), perCharacter(launched), accuracy: perCharacter(launched) * 0.12,
                       "the game count lost its font after the import")
        fresh.terminate()
    }

    /// A copy whose source stops answering (a pipe nothing writes, as an SMB share gone quiet
    /// while the app was away) never freezes the library, and its cancel ends it.
    @MainActor
    func testStalledImportCancels() {
        let app = launch(["-RetroPlayTestImportStall", "YES"])
        let button = importButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no import button while a game imports")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        XCTAssertTrue(waitFor("isHittable == true", button, timeout: 10), "the library doesn't respond after coming back")
        button.tap()
        let cancel = app.buttons["library.imports.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "no Cancel in the import status (frozen?)")
        attachScreen("import-status-stalled")
        cancel.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 15), "the stalled import didn't stop")
        XCTAssertFalse(app.alerts.firstMatch.exists, "a cancelled import shows an alert")
        // Still responsive: Settings opens.
        app.navigationBars.buttons["library.settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@", "Settings")).firstMatch.waitForExistence(timeout: 10), "Settings doesn't open after the stalled import")
        app.terminate()
    }

    /// Cancel in the status stops the copy: the button goes, and no half game is left.
    @MainActor
    func testCancelStopsTheImport() {
        let app = launch(importSeconds: 40)
        let button = importButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no import button in the top bar while a game imports")
        button.tap()
        let cancel = app.buttons["library.imports.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "no Cancel in the import status")
        cancel.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 10), "the import didn't stop")
        XCTAssertFalse(importedTile(app).exists, "a cancelled import added the game")
        app.terminate()
    }

    /// Going home mid-copy (a game from a NAS takes a while) keeps the app running until the
    /// copy is done, then lets it suspend; the game is in the library when it's back.
    @MainActor
    func testImportFinishesInTheBackground() {
        let app = launch(importSeconds: 8)
        XCTAssertTrue(waitFor("exists == true", app.descendants(matching: .any)["library.import"].firstMatch, timeout: 30))
        Thread.sleep(forTimeInterval: 1.5)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        print("[import] 3 s after home: state \(app.state.rawValue)")
        XCTAssertEqual(app.state, .runningBackground, "the app was suspended mid-import")
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 30), "the app stays awake after the import (state \(app.state.rawValue))")
        app.activate()
        XCTAssertTrue(importedTile(app).waitForExistence(timeout: 10), "the game imported in the background isn't in the library")
        XCTAssertFalse(app.alerts.firstMatch.exists, "an alert after the import: \(app.alerts.firstMatch.label)")
        app.terminate()
    }
}

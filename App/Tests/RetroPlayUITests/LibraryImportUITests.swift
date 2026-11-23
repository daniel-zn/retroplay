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
        // The import switched the filter to its system; back to All Games, so the count reads
        // the same as on a fresh launch and its width can be compared.
        app.navigationBars.buttons["library.filter"].firstMatch.tap()
        let all = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND elementType != %d", "All Games", XCUIElement.ElementType.staticText.rawValue)).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5), "no All Games in the filter menu")
        all.tap()
        Thread.sleep(forTimeInterval: 1)
        let after = titleFrames(app, "after the import")
        attachScreen("import-done")
        app.terminate()

        // The same library, launched fresh: the title and count in the RetroPlay font. After
        // the import (the count changed, the button came and went) they must still match.
        let fresh = launch()
        let launched = titleFrames(fresh, "fresh launch")
        XCTAssertEqual(after.label, launched.label)
        XCTAssertEqual(after.title.width, launched.title.width, accuracy: 1, "the title lost its font after the import")
        XCTAssertEqual(after.subtitle.width, launched.subtitle.width, accuracy: 1, "the game count lost its font after the import")
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
        let row = app.descendants(matching: .any)["library.imports.item"].firstMatch
        XCTAssertTrue(waitFor("label CONTAINS[c] 'Cancelled'", row, timeout: 15), "the stalled import didn't stop: “\(row.label)”")
        attachScreen("import-stalled-cancelled")
        // The button stays while its status is open (the popover hides the bar from
        // accessibility meanwhile), and goes with it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 10), "the button stays after its status closed")
        XCTAssertFalse(app.alerts.firstMatch.exists, "a cancelled import shows an alert")
        // Still responsive: Settings opens.
        let settings = app.descendants(matching: .any)["library.settings"].firstMatch
        XCTAssertTrue(waitFor("isHittable == true", settings, timeout: 10), "no Settings button after the stalled import")
        settings.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Settings")).firstMatch.waitForExistence(timeout: 10), "Settings doesn't open after the stalled import")
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
        let row = app.descendants(matching: .any)["library.imports.item"].firstMatch
        XCTAssertTrue(waitFor("label CONTAINS[c] 'Cancelled'", row, timeout: 10), "the import didn't stop: “\(row.label)”")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 10), "the button stays after the import stopped")
        XCTAssertFalse(importedTile(app).exists, "a cancelled import added the game")
        app.terminate()
    }

    /// Going home mid-copy (a game from a NAS takes a while) keeps the app running until the
    /// copy is done, then lets it suspend; the game is in the library when it's back.
    @MainActor
    func testImportFinishesInTheBackground() {
        let app = launch(importSeconds: 16)
        XCTAssertTrue(importButton(app).waitForExistence(timeout: 30), "no import button while a game imports")
        XCUIDevice.shared.press(.home)
        // Longer than the copy has left: a suspended app would still have most of it to do.
        Thread.sleep(forTimeInterval: 20)
        app.activate()
        XCTAssertTrue(importedTile(app).waitForExistence(timeout: 3), "the copy didn't go on in the background")
        XCTAssertFalse(importButton(app).exists, "the import is still running after coming back")
        XCTAssertFalse(app.alerts.firstMatch.exists, "an alert after the import: \(app.alerts.firstMatch.label)")
        app.terminate()
    }
    /// The import status opens every time its button is tapped, however it was closed (a tap
    /// outside, a swipe down), five times each; the import ending while it's open takes the
    /// button away; and the top bar still answers: + opens its menu, the filter its menu,
    /// Settings opens.
    @MainActor
    func testStatusOpensEveryTimeAndTheBarStaysAlive() {
        // Animations slowed, so a tap can come while the status is still closing.
        let app = launch(["-RetroPlayTestImportStall", "YES", "-RetroPlayTestAnimationSpeed", "0.2"])
        let button = importButton(app)
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no import button while a game imports")
        let row = app.descendants(matching: .any)["library.imports.item"].firstMatch
        let window = app.windows.firstMatch
        // A tap that lands while the status is still closing can be dropped, as iOS ignores
        // touches during the transition; the next one opens it (a stuck status never opens).
        func opens(_ what: String) -> Bool {
            for tap in 1...3 {
                guard waitFor("isHittable == true", button, timeout: 30) else { return false }
                button.tap()
                if row.waitForExistence(timeout: 10) {
                    print("[import] \(what): opened on tap \(tap)")
                    return true
                }
            }
            return false
        }
        for close in ["outside", "swipe"] {
            for cycle in 1...5 {
                XCTAssertTrue(opens("\(close) \(cycle)"), "\(close) \(cycle): tapping the button doesn't open the status")
                if cycle == 1 { attachScreen("import-status-\(close)") }
                if close == "outside" {
                    window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
                } else {
                    let top = row.frame.minY - 30
                    window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
                        .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
                }
                XCTAssertTrue(row.waitForNonExistence(timeout: 5), "\(close) \(cycle): the status didn't close")
            }
        }
        // Stopped with the status open: it says so, and the button goes.
        XCTAssertTrue(opens("after the cycles"), "the status doesn't open after the cycles")
        app.buttons["library.imports.cancel"].firstMatch.tap()
        XCTAssertTrue(waitFor("label CONTAINS[c] 'Cancelled'", row, timeout: 15), "the import didn't stop: “\(row.label)”")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 10), "the button stays after the import stopped")
        expectBarAnswers(app, "after the stalled import")
        app.terminate()

        // An import that finishes while its status is open (its system's filter showing).
        let second = launch(importSeconds: 10)
        let secondButton = importButton(second)
        XCTAssertTrue(secondButton.waitForExistence(timeout: 30), "no import button for the second import")
        secondButton.tap()
        let secondRow = second.descendants(matching: .any)["library.imports.item"].firstMatch
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5), "the status didn't open")
        XCTAssertTrue(waitFor("label CONTAINS[c] 'Imported'", secondRow, timeout: 40), "the import didn't finish: “\(secondRow.label)”")
        attachScreen("import-status-finished")
        second.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(secondRow.waitForNonExistence(timeout: 5), "the finished status didn't close")
        XCTAssertTrue(secondButton.waitForNonExistence(timeout: 5), "the button stays after the import finished")
        XCTAssertTrue(importedTile(second).waitForExistence(timeout: 10), "the game isn't in the library")
        expectBarAnswers(second, "after the import finished")
        second.terminate()
    }

    /// Each of the bar's buttons does its job: + and the filter open their menus, Settings opens.
    @MainActor
    private func expectBarAnswers(_ app: XCUIApplication, _ context: String) {
        let window = app.windows.firstMatch
        let plus = app.navigationBars.buttons["library.import"].firstMatch
        XCTAssertTrue(waitFor("isHittable == true", plus, timeout: 10), "\(context): + can't be tapped")
        plus.tap()
        let games = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH[c] %@", "library.import.games", "Games")).firstMatch
        XCTAssertTrue(games.waitForExistence(timeout: 5), "\(context): + didn't open its menu")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(games.waitForNonExistence(timeout: 5), "\(context): +'s menu didn't close")

        let filter = app.navigationBars.buttons["library.filter"].firstMatch
        XCTAssertTrue(waitFor("isHittable == true", filter, timeout: 10), "\(context): the filter can't be tapped")
        filter.tap()
        let all = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH[c] %@ AND elementType != %d", "All Games", XCUIElement.ElementType.staticText.rawValue)).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5), "\(context): the filter didn't open its menu")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(all.waitForNonExistence(timeout: 5), "\(context): the filter's menu didn't close")

        let settings = app.navigationBars.buttons["library.settings"].firstMatch
        XCTAssertTrue(waitFor("isHittable == true", settings, timeout: 10), "\(context): Settings can't be tapped")
        settings.tap()
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier ==[c] %@", "Settings")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "\(context): Settings didn't open")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.085))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(bar.waitForNonExistence(timeout: 10), "\(context): Settings didn't close")
    }
}

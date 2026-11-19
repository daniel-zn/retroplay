// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Settings → Saves → Saves Waiting for Games: a save imported for a game not in the library
/// is listed, and swiping it away deletes it.
final class SettingsKeptSavesUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }


    @MainActor
    func testAWaitingSaveIsListedAndCanBeDeleted() {
        let app = XCUIApplication()
        // A debug-build hook puts one GBA save in the waiting folder, then opens Settings.
        app.launchArguments = ["-RetroPlaySmokeKeptSave", "YES", "-RetroPlaySmokeSettings", "YES"]
        app.launchRetroPlay()

        // Settings is a lazy List: the Saves row exists only once it's scrolled into view.
        let settings = app.collectionViews.firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "Settings didn't open")
        let row = app.buttons["settings.keptSaves"].firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            settings.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Saves Waiting for Games row in Settings")
        attachScreen("settings-saves-section")
        row.tap()

        // Case-insensitive: the app may set its text in capitals.
        let title = NSPredicate(format: "label ==[c] %@", "Smoke Waiting Game (USA)")
        let save = app.staticTexts.matching(title).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the waiting save isn't listed")
        attachScreen("settings-waiting-saves")

        let cell = app.cells.containing(title).firstMatch
        (cell.exists ? cell : save).swipeLeft()
        let delete = app.buttons.labelled("Delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete action on the row")
        delete.tap()

        let empty = app.staticTexts.labelled("No Waiting Saves")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "the save is still listed")
        attachScreen("settings-waiting-saves-deleted")
    }
}

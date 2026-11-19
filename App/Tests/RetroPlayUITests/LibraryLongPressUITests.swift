// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// A long press on a cover lifts just the cover, at its own size and shape (each system's box),
/// with nothing around it; Delete in its menu asks first, in the system's own alert.
///
/// Needs a DS, a PSP and a GBA game in the library. The test Simulator's DS game is an empty
/// `Shape Test.nds` in its Games folder (no ROM is needed to long-press a cover).
final class LibraryLongPressUITests: XCTestCase {
    /// Each system's box shape (width / height) when it has no box art.
    private let systems: [(name: String, aspect: CGFloat)] = [
        ("Nintendo DS", 1.1), ("PlayStation Portable", 0.58), ("Game Boy Advance", 1.0),
    ]

    @MainActor
    func testCoverFlowPreviewIsTheCover() {
        let app = XCUIApplication()
        app.launchArguments = ["-retroplay.libraryLayout", "coverFlow", "-RetroPlaySmokePortrait", "YES"]
        app.launchRetroPlay()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["coverFlow.position"].waitForExistence(timeout: 30), "no Cover Flow")
        for system in systems {
            guard let cover = bringToMiddle(app, system.name) else {
                XCTFail("no \(system.name) game in the library")
                continue
            }
            cover.press(forDuration: 1.2)
            let preview = app.descendants(matching: .any)["library.coverPreview"]
            guard preview.waitForExistence(timeout: 5) else {
                XCTFail("\(system.name): no preview")
                continue
            }
            waitUntilStill(preview)
            attachScreen("longpress-coverflow-\(system.name)")
            let frame = preview.frame, slot = cover.frame
            // Every cover is as wide as its slot and as tall as its shape makes it.
            XCTAssertEqual(frame.width / frame.height, system.aspect, accuracy: 0.03,
                           "\(system.name): the preview is \(frame.size), not the cover's shape")
            XCTAssertEqual(frame.width, slot.width, accuracy: 2,
                           "\(system.name): the preview is \(frame.width) wide, the cover \(slot.width)")
            dismissMenu(app)
        }
    }

    /// Delete in the cover's menu asks in the system's alert; Cancel keeps the game.
    @MainActor
    func testDeleteAsksInTheSystemAlert() {
        let app = XCUIApplication()
        app.launchArguments = ["-retroplay.libraryLayout", "coverFlow", "-RetroPlaySmokePortrait", "YES"]
        app.launchRetroPlay()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["coverFlow.position"].waitForExistence(timeout: 30), "no Cover Flow")
        guard let cover = bringToMiddle(app, "Game Boy Advance") else { return XCTFail("no GBA game") }
        let label = cover.label
        cover.press(forDuration: 1.2)
        let delete = app.buttons.labelled("Delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete in the menu")
        delete.tap()
        let alert = app.alerts["Delete Game?"]
        let shown = alert.waitForExistence(timeout: 5)
        attachScreen("alert-delete-game")
        // Cancel, whichever way it's drawn, so the game stays.
        let cancel = shown ? alert.buttons["Cancel"] : app.buttons.labelled("Cancel")
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        XCTAssertTrue(shown, "Delete didn't ask in the system's alert")
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "Cancel deleted the game")
    }

    /// The grid's long press: a screenshot per system (the lift's shape isn't in the
    /// accessibility tree, so it's judged by eye).
    @MainActor
    func testGridPreviewShots() {
        let app = XCUIApplication()
        app.launchArguments = ["-retroplay.libraryLayout", "grid", "-RetroPlaySmokePortrait", "YES"]
        app.launchRetroPlay()
        defer { app.terminate() }
        for system in systems {
            let tile = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", \(system.name)")).firstMatch
            guard tile.waitForExistence(timeout: 30) else {
                XCTFail("no \(system.name) tile")
                continue
            }
            if !tile.isHittable { app.swipeUp() }
            tile.press(forDuration: 1.2)
            Thread.sleep(forTimeInterval: 1)
            attachScreen("longpress-grid-\(system.name)")
            dismissMenu(app)
        }
    }

    /// Moves the row until a cover of `system` is in the middle (a tap on a side cover brings it
    /// there); that cover's button.
    @MainActor
    private func bringToMiddle(_ app: XCUIApplication, _ system: String) -> XCUIElement? {
        let middleX = app.windows.firstMatch.frame.midX
        for _ in 0..<8 {
            let covers = app.buttons.allElementsBoundByIndex.filter {
                $0.label.hasSuffix(", \(system)") && $0.frame.height > 100
            }
            guard let cover = covers.min(by: { abs($0.frame.midX - middleX) < abs($1.frame.midX - middleX) }) else {
                app.windows.firstMatch.swipeLeft()
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            // Side covers' slots are a step (120 pt or more) away; a tap on the middle one plays it.
            if abs(cover.frame.midX - middleX) < cover.frame.width / 4 { return cover }
            cover.tap()
            Thread.sleep(forTimeInterval: 1.2)
        }
        return nil
    }

    @MainActor
    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 1)
    }
}

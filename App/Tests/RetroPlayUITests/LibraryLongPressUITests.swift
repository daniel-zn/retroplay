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

    /// Moves the row until a cover of `system` is in the middle; that cover's button. The covers are listed in
    /// row order and `coverFlow.position` is the middle one's index.
    @MainActor
    private func bringToMiddle(_ app: XCUIApplication, _ system: String) -> XCUIElement? {
        let position = app.descendants(matching: .any)["coverFlow.position"]
        for _ in 0..<6 {
            guard position.exists, let middle = Int(position.value as? String ?? "") else { return nil }
            let covers = app.buttons.allElementsBoundByIndex.filter { $0.label.contains(", ") && $0.frame.height > 100 }
            print("[long-press] middle \(middle) of \(covers.map { "\($0.label) \(Int($0.frame.midX))" })")
            guard middle < covers.count else { return nil }
            if covers[middle].label.hasSuffix(", \(system)") { return covers[middle] }
            guard let target = covers.first(where: { $0.label.hasSuffix(", \(system)") }) else { return nil }
            // Dragged the distance between their slots and held (no fling): a tap at a side
            // cover's frame can land on the middle one, which stacks over its slot.
            let from = covers[middle].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.1,
                       thenDragTo: from.withOffset(CGVector(dx: covers[middle].frame.midX - target.frame.midX, dy: 0)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 1.5)
        }
        return nil
    }

    @MainActor
    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 1)
    }
}

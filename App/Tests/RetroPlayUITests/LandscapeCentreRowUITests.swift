// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Landscape, per system: fast-forward, pause and sound sit together at the bottom centre (as
/// in portrait), the small buttons (SELECT, START, the 7800's switches) either side of them,
/// all on one row, clear of the game picture and of the D-pad and face buttons. At the
/// default text size and the largest the controls follow (XXXL). Screenshots attached.
final class LandscapeCentreRowUITests: XCTestCase {
    /// Systems with a game in the Simulator's library (others are skipped and named).
    private var systems: [String] {
        (ProcessInfo.processInfo.environment["RETROPLAY_LAYOUT_SYSTEMS"] ?? "nes,snes,gba,n64,ps1,psp,genesis,atari7800")
            .split(separator: ",").map(String.init)
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func labelled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    @discardableResult
    private func check(_ system: String, size: String, look: String) -> Bool {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // The Simulator counts the Mac's keyboard as a controller, which hides the touch
        // controls; they're shown with one, as a player can choose.
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", size, "-RetroPlaySmokeSystem", system,
                               "-retroplay.touchWithController", "YES",
                               // The fitted layout (a Simulator may remember Fill Screen in
                               // Landscape, where the picture runs under the controls on purpose).
                               "-retroplay.landscapeFill.\(system)", "NO"]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        defer { app.terminate() }
        let pause = app.buttons["Pause menu"].firstMatch
        guard pause.waitForExistence(timeout: 45) else {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "row-\(system)-\(look)-no-game"
            shot.lifetime = .keepAlways
            add(shot)
            let note = XCTAttachment(string: "\(system): no game for it in this Simulator's library, not checked")
            note.name = "row-\(system)-\(look)-skipped"
            note.lifetime = .keepAlways
            add(note)
            return false
        }
        // The game runs a moment so the picture is drawn behind the controls.
        Thread.sleep(forTimeInterval: 6)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "row-\(system)-\(look)"
        shot.lifetime = .keepAlways
        add(shot)

        let window = app.windows.firstMatch.frame
        let context = "\(system) \(look)"
        XCTAssertGreaterThan(window.width, window.height, "\(context): not in landscape")
        let fastForward = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fast forward")).firstMatch
        let sound = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sound")).firstMatch
        let group = [fastForward, pause, sound].map(\.frame).reduce(CGRect.null) { $0.union($1) }
        XCTAssertLessThan(abs(group.midX - window.midX), 24, "\(context): fast-forward / pause / sound \(group) aren't centred in \(window)")
        XCTAssertGreaterThan(group.maxY, window.maxY - 60, "\(context): fast-forward / pause / sound \(group) aren't at the bottom")

        var small: [CGRect] = []
        for title in ["SELECT", "START", "PAUSE", "RESET"] {
            let pill = labelled(app, title)
            guard pill.exists else { continue }
            let frame = pill.frame
            small.append(frame)
            XCTAssertLessThan(abs(frame.midY - group.midY), 24, "\(context): \(title) \(frame) isn't on the row \(group)")
            if title == "SELECT" {
                XCTAssertLessThanOrEqual(frame.maxX, group.minX + 1, "\(context): SELECT \(frame) isn't left of \(group)")
            } else {
                XCTAssertGreaterThanOrEqual(frame.minX, group.maxX - 1, "\(context): \(title) \(frame) isn't right of \(group)")
            }
        }
        XCTAssertFalse(small.isEmpty, "\(context): no small buttons found")

        // Clear of the picture (fitted between the columns) and of the thumb controls. The
        // small buttons' touch areas reach past what's drawn, so a few points of overlap are
        // allowed.
        let row = small.reduce(group) { $0.union($1) }
        let picture = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " screen")).firstMatch
        if picture.exists {
            XCTAssertLessThan(row.intersection(picture.frame).height, 12, "\(context): the row \(row) covers the picture \(picture.frame)")
        }
        for title in ["D-pad", "A", "B", "X", "Y", "C", "1", "2", "Triangle", "Circle", "Cross", "Square"] {
            let control = labelled(app, title)
            guard control.exists else { continue }
            for frame in [group] + small {
                XCTAssertTrue(frame.insetBy(dx: 6, dy: 6).intersection(control.frame).isNull,
                              "\(context): \(frame) overlaps \(title) \(control.frame)")
            }
        }
        return true
    }

    @MainActor
    func testTheRowAtTheDefaultTextSize() {
        let checked = systems.filter { check($0, size: "UICTContentSizeCategoryL", look: "default") }
        XCTAssertFalse(checked.isEmpty, "no system had a game to check")
    }

    @MainActor
    func testTheRowAtTheLargestTextSize() {
        let checked = systems.filter { check($0, size: "UICTContentSizeCategoryXXXL", look: "xxxl") }
        XCTAssertFalse(checked.isEmpty, "no system had a game to check")
    }
}

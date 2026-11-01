// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The pause menu with Saves and Options open stays within the screen and every row can be
/// reached (scrolled into view), in portrait and landscape, at the default text size and the
/// largest accessibility size. Screenshots of each are attached.
final class PauseMenuFitUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "pause-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
            .firstMatch
    }

    /// Drags the menu's content up (`down: false`) or down by most of a screen.
    @MainActor
    private func drag(_ app: XCUIApplication, down: Bool) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.7))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.3))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    /// Scrolls until `label` is on screen and can be tapped; nil if it never is.
    @MainActor
    @discardableResult
    private func reach(_ app: XCUIApplication, _ label: String, _ context: String) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        for down in [false, true] {
            for _ in 0..<8 {
                let row = element(app, label)
                if row.exists, row.isHittable, window.insetBy(dx: -1, dy: -1).contains(row.frame) { return row }
                drag(app, down: down)
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        shoot("\(context)-unreachable-\(label)")
        XCTFail("\(context): “\(label)” can't be scrolled into view (frame \(element(app, label).frame), window \(window))")
        return nil
    }

    @MainActor
    private func check(_ orientation: UIDeviceOrientation, _ size: String, _ name: String) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", size,
            "-RetroPlaySmokeSystem", "nes", "-RetroPlaySmokeMenu", "YES",
        ]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        defer { app.terminate() }
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Resume")).firstMatch
        guard resume.waitForExistence(timeout: 45) else {
            XCTFail("\(name): no pause menu")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        shoot("\(name)-closed")

        reach(app, "Saves", name)?.tap()
        Thread.sleep(forTimeInterval: 0.6)
        reach(app, "Options", name)?.tap()
        Thread.sleep(forTimeInterval: 0.8)
        shoot("\(name)-open")

        // Every row, bottom ones first (most likely past the screen), then back to the top.
        for label in ["Quit Game", "Fill Screen in Landscape", "Smooth Screen", "Haptics", "Options",
                      "Import Battery Save…", "Reset", "No saves yet", "Saves", "Save state", "Resume"] {
            reach(app, label, name)
        }
        shoot("\(name)-top")
        // The menu itself: inside the screen, whatever its content.
        let menu = app.otherElements["playMenu"].firstMatch
        guard menu.exists else {
            XCTFail("\(name): no menu")
            return
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(menu.frame), "\(name): the menu \(menu.frame) runs past the screen \(window)")
    }

    @MainActor
    func testPortraitAtTheDefaultAndLargestTextSizes() {
        check(.portrait, "UICTContentSizeCategoryL", "portrait-default")
        check(.portrait, "UICTContentSizeCategoryAccessibilityXXXL", "portrait-ax5")
    }

    @MainActor
    func testLandscapeAtTheDefaultAndLargestTextSizes() {
        check(.landscapeLeft, "UICTContentSizeCategoryL", "landscape-default")
        check(.landscapeLeft, "UICTContentSizeCategoryAccessibilityXXXL", "landscape-ax5")
    }
}

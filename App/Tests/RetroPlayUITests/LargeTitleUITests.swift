// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The library's and Settings' titles are iOS's own large navigation titles (in the bar, not
/// drawn in the page), set big in the title face: well over the old 30-point size at the
/// default text size, and whole and inside the screen at the largest text sizes.
final class LargeTitleUITests: XCTestCase {
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

    /// The title text in the navigation bar, once it's there.
    @MainActor
    private func barTitle(_ app: XCUIApplication, _ title: String, _ context: String) -> XCUIElement {
        let texts = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title))
        XCTAssertTrue(texts.firstMatch.waitForExistence(timeout: 30), "\(context): “\(title)” isn't a navigation-bar title")
        // The bar can hold the collapsed (inline) title too: the large one is the tallest.
        let all = texts.allElementsBoundByIndex
        return all.max { $0.frame.height < $1.frame.height } ?? texts.firstMatch
    }

    @MainActor
    private func check(_ app: XCUIApplication, _ title: String, _ size: String, minimumHeight: CGFloat) {
        let text = barTitle(app, title, "\(title) \(size)")
        let window = app.windows.firstMatch.frame
        let frame = text.frame
        print("[large-title] \(title) \(size): \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, minimumHeight, "\(title) \(size): the title is small: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(title) \(size): the title runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "\(title) \(size): the title runs off the right: \(frame)")
        XCTAssertLessThan(frame.maxY, window.height * 0.35, "\(title) \(size): the title isn't at the top: \(frame)")
        attach("large-title-\(title)-\(size)")
    }

    /// 42 points at the default size: about 50 tall. The old 30-point one was about 36.
    @MainActor
    func testLibraryTitleIsALargeNavigationTitle() {
        for (size, minimum) in [("UICTContentSizeCategoryL", 44.0), ("UICTContentSizeCategoryAccessibilityXXXL", 44.0)] {
            for layout in ["grid", "coverFlow"] {
                let app = launch(["-UIPreferredContentSizeCategoryName", size, "-retroplay.libraryLayout", layout])
                check(app, "RetroPlay", "\(layout)-\(size)", minimumHeight: minimum)
                app.terminate()
            }
        }
    }

    @MainActor
    func testSettingsTitleIsALargeNavigationTitle() {
        for (size, minimum) in [("UICTContentSizeCategoryL", 44.0), ("UICTContentSizeCategoryAccessibilityXXXL", 44.0)] {
            let app = launch(["-UIPreferredContentSizeCategoryName", size, "-RetroPlaySmokeSettings", "YES"])
            check(app, "Settings", size, minimumHeight: minimum)
            app.terminate()
        }
    }
}

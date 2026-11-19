// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

// How every RetroPlay UI test launches, finds, waits and takes screenshots, so a waiting bug
// is fixed in one place.

extension XCUIApplication {
    /// Launches with the test runner's DYLD_* paths cleared: they point at the build folder,
    /// where the emulator cores sit unsigned; the app's own signed copies are the ones to load.
    func launchRetroPlay() {
        launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        launch()
    }
}

extension XCUIElementQuery {
    /// The first element with this label, in any case (the app capitalises some labels).
    func labelled(_ label: String) -> XCUIElement {
        matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }
}

extension XCTestCase {
    /// A screenshot kept with the results. The screen, not the app: in landscape
    /// `app.screenshot()` comes out rotated twice.
    func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits until `format` (a predicate on the element, "isHittable == true") holds.
    func waitFor(_ format: String, _ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits until `element` stops moving (a drag's scroll or an animation has settled): the
    /// same frame on two looks 0.1 s apart, or gone. False if it still moves after `timeout`.
    @MainActor
    @discardableResult
    func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var last = element.exists ? element.frame : .null
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            let now = element.exists ? element.frame : .null
            if now == last { return true }
            last = now
        }
        return false
    }
}

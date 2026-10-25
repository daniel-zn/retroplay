// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The library's top-right buttons: in order, close together in one capsule, each still a full
/// touch target, at the default text size and at a large one.
final class LibraryTopBarUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTopBarButtonsSitCloseTogether() {
        let ids = ["library.import", "library.filter", "library.search", "library.settings"]
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", size]
            // Xcode points test launches at the build folder for frameworks, where the
            // emulator cores sit unsigned; the app's own signed copies are the ones to load.
            app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
            app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
            app.launch()
            let buttons = ids.map { app.buttons[$0].firstMatch }
            for (id, button) in zip(ids, buttons) {
                XCTAssertTrue(button.waitForExistence(timeout: 30), "\(size): no \(id)")
            }
            sleep(1)
            let frames = buttons.map { $0.frame }
            // Icon centres no more than 48 pt apart (a toolbar group, or icons built as labels,
            // put 55-66 pt between them), each at least 44 pt wide to touch.
            let steps = zip(frames.dropFirst(), frames).map { $0.midX - $1.midX }
            print("[top-bar] \(size): \(frames), centres \(steps) pt apart")
            for step in steps {
                XCTAssertGreaterThan(step, 0, "\(size): the buttons are out of order: \(steps)")
                XCTAssertLessThanOrEqual(step, 48, "\(size): the icons are \(steps) pt apart")
            }
            for (id, frame) in zip(ids, frames) {
                XCTAssertGreaterThanOrEqual(frame.width, 44, "\(size): \(id) is \(frame.size), under 44 pt wide")
                XCTAssertEqual(frame.midY, frames[0].midY, accuracy: 2, "\(size): \(id) isn't in the row")
                XCTAssertLessThan(frame.maxY, 140, "\(size): \(id) isn't at the top")
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "top-bar-\(size)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}

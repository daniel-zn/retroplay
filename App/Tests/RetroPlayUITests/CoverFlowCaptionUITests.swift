// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The caption under Cover Flow's middle game (title, system / last played): on screen and
/// clear of the covers, in portrait and landscape, at the default text size and XXXL.
/// Screenshots attached.
final class CoverFlowCaptionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func check(_ orientation: UIDeviceOrientation, _ size: String, _ name: String) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", size, "-retroplay.libraryLayout", "coverFlow",
                               // The caption is hidden from VoiceOver; debug builds expose it for this check.
                               "-RetroPlayTestCaptionAccessible", "YES"]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        defer { app.terminate() }
        let caption = app.descendants(matching: .any)["coverFlow.caption"].firstMatch
        guard caption.waitForExistence(timeout: 30) else {
            XCTFail("\(name): no caption")
            return
        }
        Thread.sleep(forTimeInterval: 2)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "coverflow-caption-\(name)"
        shot.lifetime = .keepAlways
        add(shot)

        let window = app.windows.firstMatch.frame
        let frame = caption.frame
        XCTAssertFalse(frame.isEmpty, "\(name): the caption has no size")
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame), "\(name): the caption \(frame) runs off the screen \(window)")
        let covers = app.buttons.allElementsBoundByIndex.filter { $0.label.contains(", ") && $0.frame.height > 100 }
        guard let middle = covers.min(by: { abs($0.frame.midX - window.midX) < abs($1.frame.midX - window.midX) }) else {
            XCTFail("\(name): no covers")
            return
        }
        XCTAssertGreaterThanOrEqual(frame.minY, middle.frame.maxY - 2, "\(name): the caption \(frame) runs into the middle cover \(middle.frame)")
    }

    @MainActor
    func testPortrait() {
        check(.portrait, "UICTContentSizeCategoryL", "portrait-default")
        check(.portrait, "UICTContentSizeCategoryXXXL", "portrait-xxxl")
    }

    @MainActor
    func testLandscape() {
        check(.landscapeLeft, "UICTContentSizeCategoryL", "landscape-default")
        check(.landscapeLeft, "UICTContentSizeCategoryXXXL", "landscape-xxxl")
    }
}

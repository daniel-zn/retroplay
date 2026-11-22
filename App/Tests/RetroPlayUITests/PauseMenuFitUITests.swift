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
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@", label, label + ","))
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

    /// Scrolls until `label` lies wholly inside the menu's visible area and the screen; nil if
    /// it never does. Judged by frames, not XCUITest's accessibility hit-test, which can land on
    /// the game screen listed beside the menu.
    @MainActor
    @discardableResult
    private func reach(_ app: XCUIApplication, _ label: String, _ context: String) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        let menu = app.descendants(matching: .any)["playMenu"].firstMatch
        for down in [false, true] {
            for _ in 0..<8 {
                let row = element(app, label)
                if row.exists, menu.exists {
                    let frame = row.frame
                    let visible = menu.frame.intersection(window).insetBy(dx: -1, dy: -1)
                    if !frame.isEmpty, visible.contains(frame) { return row }
                }
                drag(app, down: down)
                waitUntilStill(element(app, label))
            }
        }
        attachScreen("pause-\(context)-unreachable-\(label)")
        XCTFail("\(context): “\(label)” can't be scrolled into view (frame \(element(app, label).frame), menu \(menu.frame), window \(window))")
        return nil
    }

    /// Scrolls `label` into view and taps where it's drawn.
    @MainActor
    private func tapRow(_ app: XCUIApplication, _ label: String, _ context: String) {
        reach(app, label, context)?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func check(_ orientation: UIDeviceOrientation, _ size: String, _ name: String) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", size,
            "-RetroPlaySmokeSystem", "nes", "-RetroPlaySmokeMenu", "YES",
        ]
        app.launchRetroPlay()
        defer { app.terminate() }
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Resume")).firstMatch
        guard resume.waitForExistence(timeout: 45) else {
            XCTFail("\(name): no pause menu")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        attachScreen("pause-\(name)-closed")

        tapRow(app, "Saves", name)
        Thread.sleep(forTimeInterval: 0.6)
        tapRow(app, "Options", name)
        Thread.sleep(forTimeInterval: 0.8)
        attachScreen("pause-\(name)-open")

        // Every row, bottom ones first (most likely past the screen), then back to the top.
        for label in ["Quit Game", "Fill Screen in Landscape", "Smooth Screen", "Haptics", "Options",
                      "Import Battery Save…", "Reset", "No saves yet", "Saves", "Save state", "Resume"] {
            reach(app, label, name)
        }
        attachScreen("pause-\(name)-top")
        // The menu itself: inside the screen, whatever its content.
        // The menu is a scroll view (any element type is matched).
        let menu = app.descendants(matching: .any)["playMenu"].firstMatch
        guard menu.exists else {
            XCTFail("\(name): no menu")
            return
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(menu.frame), "\(name): the menu \(menu.frame) runs past the screen \(window)")
    }

    /// Options' switches are drawn whole (a capsule's rounded right end, not sliced flat by
    /// the card's content edge) and sit inside the card with room to spare; the title above and
    /// Quit Game below can each be scrolled wholly into the card, clear of its edges.
    @MainActor
    func testSwitchesAndQuitSitWhollyInsideTheCard() {
        for (orientation, size, name) in [(UIDeviceOrientation.landscapeLeft, "UICTContentSizeCategoryL", "landscape-default"),
                                          (.landscapeLeft, "UICTContentSizeCategoryAccessibilityXXXL", "landscape-ax5"),
                                          (.portrait, "UICTContentSizeCategoryL", "portrait-default"),
                                          (.portrait, "UICTContentSizeCategoryAccessibilityXXXL", "portrait-ax5")] {
            XCUIDevice.shared.orientation = orientation
            let app = XCUIApplication()
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", size,
                                   "-RetroPlaySmokeSystem", "nes", "-RetroPlaySmokeMenu", "YES"]
            app.launchRetroPlay()
            let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Resume")).firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 45), "\(name): no pause menu")
            Thread.sleep(forTimeInterval: 1)
            tapRow(app, "Saves", name)
            Thread.sleep(forTimeInterval: 0.6)
            tapRow(app, "Options", name)
            Thread.sleep(forTimeInterval: 0.8)
            let menu = app.descendants(matching: .any)["playMenu"].firstMatch
            let card = menu.frame.intersection(app.windows.firstMatch.frame)
            for label in ["Haptics", "Smooth Screen", "Fill Screen in Landscape"] {
                guard let row = reach(app, label, name) else { continue }
                waitUntilStill(row)
                let toggle = app.switches[label].firstMatch
                let frame = toggle.exists ? toggle.frame : row.frame
                XCTAssertLessThanOrEqual(frame.maxX, card.maxX - 12, "\(name): “\(label)” \(frame) runs to the card's edge \(card)")
                XCTAssertGreaterThanOrEqual(frame.minX, card.minX + 12, "\(name): “\(label)” \(frame) runs to the card's edge \(card)")
                let shot = XCUIScreen.main.screenshot()
                if let ratio = Self.rightEndNarrowing(shot.image, rowFrame: frame, landscape: orientation.isLandscape) {
                    print("[pause] \(name) \(label) right-end height ratio \(ratio)")
                    XCTAssertLessThan(ratio, 0.6, "\(name): “\(label)”'s switch is sliced flat on its right (end/body height \(ratio))")
                } else {
                    XCTFail("\(name): “\(label)”'s switch wasn't found in the shot")
                }
                attachScreen("pause-\(name)-\(label)")
            }
            for label in ["Quit Game", "Resume"] {
                guard let row = reach(app, label, name) else { continue }
                waitUntilStill(row)
                Thread.sleep(forTimeInterval: 0.4)
                let frame = row.frame
                let visible = menu.frame.intersection(app.windows.firstMatch.frame)
                XCTAssertTrue(visible.insetBy(dx: 8, dy: 8).contains(frame),
                              "\(name): “\(label)” \(frame) isn't wholly inside the card \(visible) with room around it")
                attachScreen("pause-\(name)-reached-\(label)")
            }
            app.terminate()
        }
    }

    /// For the switch at a row's trailing end: how tall it's drawn 1 pt in from its right end,
    /// over how tall it's drawn 16 pt in. A capsule narrows to its end (well under 0.6); one
    /// sliced flat stays full height (about 1). Nil if no switch is found. A landscape screen's
    /// shot comes upright as the portrait screen (the landscape top along its right side).
    private static func rightEndNarrowing(_ image: UIImage, rowFrame: CGRect, landscape: Bool) -> Double? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(max(cg.width, cg.height)) / max(image.size.width, image.size.height)
        let width = cg.width, height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let (px, py) = landscape && width < height ? (width - 1 - y, x) : (x, y)
            let i = (min(max(py, 0), height - 1) * width + min(max(px, 0), width - 1)) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        let cy = Int(rowFrame.midY * scale)
        let start = Int((rowFrame.maxX + 6) * scale)
        let bg = pixel(start, cy)
        func drawn(_ x: Int, _ y: Int) -> Bool {
            let p = pixel(x, y)
            return abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) > 60
        }
        // The switch's right end: the first drawn pixel left of the row's end, on its middle line.
        var right = start
        while right > start - Int(60 * scale), !drawn(right, cy) { right -= 1 }
        guard drawn(right, cy) else { return nil }
        func columnHeight(_ x: Int) -> Int {
            var top = cy, bottom = cy
            while top > cy - Int(30 * scale), drawn(x, top - 1) { top -= 1 }
            while bottom < cy + Int(30 * scale), drawn(x, bottom + 1) { bottom += 1 }
            return bottom - top + 1
        }
        let end = columnHeight(right - Int(1 * scale))
        let body = columnHeight(right - Int(16 * scale))
        return body > 0 ? Double(end) / Double(body) : nil
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

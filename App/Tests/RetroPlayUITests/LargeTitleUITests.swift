// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The library's and Settings' titles are large navigation titles (in the bar's large-title
/// place, collapsing into the bar), set big in the title face: well over the old 30-point size
/// at the default text size, whole and inside the screen at the largest text sizes, and they
/// glitch like the app's other titles. With the glitch off (as here, but in the glitch test) the
/// big title is the bar's own, which VoiceOver and these tests can read.
final class LargeTitleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String], glitchFrame: Int = -1) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-RetroPlayTitleGlitchFrame", String(glitchFrame)]
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

    /// The large title's text, once it's there.
    @MainActor
    private func barTitle(_ app: XCUIApplication, _ title: String, _ context: String) -> XCUIElement {
        let texts = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title))
        XCTAssertTrue(texts.firstMatch.waitForExistence(timeout: 30), "\(context): no “\(title)” title")
        // The bar holds the collapsed (inline) title too: the large one is the tallest.
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

    /// A burst's first frame held (`-RetroPlayTitleGlitchFrame 0`, which always smears the line
    /// in lime and violet): the big titles show it. The plain title is white on black, so any
    /// strongly coloured pixels in its box are the glitch.
    @MainActor
    func testLargeTitlesGlitch() {
        for (title, arguments) in [("RetroPlay", ["-retroplay.libraryLayout", "grid"]),
                                   ("RetroPlay", ["-retroplay.libraryLayout", "coverFlow"]),
                                   ("Settings", ["-RetroPlaySmokeSettings", "YES"])] {
            let app = launch(arguments + ["-retroplay.appearance", "dark"], glitchFrame: 0)
            // The bar doesn't expose its large-title item: look in the bar under its buttons.
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 30), "\(title) glitch: no “\(title)” bar")
            Thread.sleep(forTimeInterval: 1)
            let frame = bar.frame
            let titleRoom = CGRect(x: frame.minX + 12, y: frame.minY + 48, width: frame.width - 24, height: frame.height - 60)
            let shot = XCUIScreen.main.screenshot()
            let coloured = Self.colouredPixels(in: shot.image, rect: titleRoom)
            print("[large-title] \(title) \(arguments) glitch frame 0: \(coloured) coloured pixels in \(titleRoom)")
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "large-title-glitch-\(title)-\(arguments.last ?? "")"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(coloured, 200, "\(title) \(arguments): the big title doesn't glitch")
            app.terminate()
        }
    }

    /// Pixels in `rect` (points, padded for the smear) with strong colour: lime, violet.
    private static func colouredPixels(in image: UIImage, rect: CGRect) -> Int {
        guard let cg = image.cgImage else { return 0 }
        let scale = CGFloat(cg.width) / image.size.width
        let box = rect.insetBy(dx: -12, dy: -12)
        let crop = CGRect(x: box.minX * scale, y: box.minY * scale, width: box.width * scale, height: box.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let part = cg.cropping(to: crop) else { return 0 }
        let w = part.width, h = part.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        var count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            if max(r, g, b) - min(r, g, b) > 70 { count += 1 }
        }
        return count
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

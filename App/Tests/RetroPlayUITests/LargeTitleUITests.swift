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

    /// `glitchFrame` nil: the glitch as it plays (the app's own big title).
    private func launch(_ arguments: [String], glitchFrame: Int? = -1) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + (glitchFrame.map { ["-RetroPlayTitleGlitchFrame", String($0)] } ?? [])
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

    /// 42 points at the default size: about 50 tall. The old 30-point one was about 36. The grid's
    /// and Settings' titles are checked the same way in `testGlitchingTitleSitsWhereTheSystemTitleDoes`
    /// (its launches with the bar's own title), so only Cover Flow's has its own launches here.
    @MainActor
    func testLibraryTitleIsALargeNavigationTitle() {
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(["-UIPreferredContentSizeCategoryName", size, "-retroplay.libraryLayout", "coverFlow"])
            check(app, "RetroPlay", "coverFlow-\(size)", minimumHeight: 44)
            app.terminate()
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

    /// The glitching big title (the app's own, in the bar's large-title place) stands where the
    /// bar's own large title does: as far under the bar's buttons, and as far in from the left,
    /// at the default and the largest text size. Found by its ink (white on black).
    @MainActor
    func testGlitchingTitleSitsWhereTheSystemTitleDoes() {
        // Every place and size measured, so a miss shows how it scales.
        continueAfterFailure = true
        for (title, arguments) in [("RetroPlay", ["-retroplay.libraryLayout", "grid"]),
                                   ("Settings", ["-RetroPlaySmokeSettings", "YES"])] {
            for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
                var ink: [String: CGRect] = [:]
                for (kind, frame) in [("system", Optional(-1)), ("glitching", nil)] as [(String, Int?)] {
                    let app = launch(arguments + ["-retroplay.appearance", "dark", "-UIPreferredContentSizeCategoryName", size],
                                     glitchFrame: frame)
                    let bar = app.navigationBars[title]
                    XCTAssertTrue(bar.waitForExistence(timeout: 30), "\(title) \(size) \(kind): no bar")
                    Thread.sleep(forTimeInterval: 1.5)
                    // A burst can smear the line: the lowest top over a few looks is the title's own.
                    var best: CGRect?
                    for _ in 0..<6 {
                        let shot = XCUIScreen.main.screenshot()
                        if let found = Self.inkBox(in: shot.image, rect: CGRect(x: 8, y: bar.frame.minY,
                                                                                  width: bar.frame.width * 0.55,
                                                                                  height: bar.frame.height)),
                           found.minY > (best?.minY ?? -1) {
                            best = found
                        }
                        Thread.sleep(forTimeInterval: 0.2)
                    }
                    print("[large-title] \(title) \(size) \(kind): bar \(bar.frame) ink \(String(describing: best))")
                    attach("title-place-\(title)-\(size)-\(kind)")
                    ink[kind] = best
                    // The bar's own big title (the glitch off): large, whole and at the top.
                    if frame != nil {
                        check(app, title, "\(arguments.last ?? "")-\(size)", minimumHeight: 44)
                    }
                    app.terminate()
                }
                print("[large-title] place \(title) \(size): system \(String(describing: ink["system"])) glitching \(String(describing: ink["glitching"]))")
                guard let system = ink["system"], let glitching = ink["glitching"] else {
                    XCTFail("\(title) \(size): no title ink found")
                    continue
                }
                XCTAssertEqual(glitching.minY, system.minY, accuracy: 2,
                               "\(title) \(size): the glitching title's top is at \(glitching.minY), the system's at \(system.minY)")
                XCTAssertEqual(glitching.minX, system.minX, accuracy: 2,
                               "\(title) \(size): the glitching title starts at \(glitching.minX), the system's at \(system.minX)")
            }
        }
    }

    /// The box (points) of the bright pixels in `rect`: rows and columns with a few of them.
    private static func inkBox(in image: UIImage, rect: CGRect) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / image.size.width
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let part = cg.cropping(to: crop) else { return nil }
        let w = part.width, h = part.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rows = [Int](repeating: 0, count: h), columns = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) > 600 { rows[y] += 1; columns[x] += 1 }
            }
        }
        guard let top = rows.firstIndex(where: { $0 >= 3 }), let bottom = rows.lastIndex(where: { $0 >= 3 }),
              let left = columns.firstIndex(where: { $0 >= 3 }), let right = columns.lastIndex(where: { $0 >= 3 })
        else { return nil }
        return CGRect(x: rect.minX + CGFloat(left) / scale, y: rect.minY + CGFloat(top) / scale,
                      width: CGFloat(right - left + 1) / scale, height: CGFloat(bottom - top + 1) / scale)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// No bar of its own: once content scrolls under it, the top bar draws no background and no
/// hairline (iOS 26); content passes under its glass buttons with iOS's scroll edge effect.
/// Measured in Settings and a screen pushed from it, beside the list's cards, where the canvas
/// runs up under the bar: every pixel of the bar's band there matches the canvas below it.
final class NavigationBarBackgroundUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testScrolledBarHasNoBackgroundOrHairline() {
        for appearance in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["-RetroPlaySmokeSettings", "YES", "-retroplay.appearance", appearance,
                                   "-RetroPlayTitleGlitchFrame", "-1"]
            app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
            app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
            app.launch()
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 30), "\(appearance): Settings didn't open")
            Thread.sleep(forTimeInterval: 1)
            scroll(app)
            expectNoBar(app, "settings-\(appearance)")

            // A pushed screen: Open Source Licenses, at the end of Settings.
            let licenses = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open Source")).firstMatch
            for _ in 0..<8 where !(licenses.exists && licenses.isHittable) { list.swipeUp() }
            XCTAssertTrue(licenses.isHittable, "\(appearance): no Open Source Licenses row")
            licenses.tap()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10),
                          "\(appearance): Licenses didn't open")
            Thread.sleep(forTimeInterval: 1)
            scroll(app)
            expectNoBar(app, "licenses-\(appearance)")
            app.terminate()
        }
    }

    /// Content scrolled well under the bar, then left to settle.
    @MainActor
    private func scroll(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// The bar's band, beside the cards, from its middle down past its bottom edge (where the
    /// hairline was), against the canvas a little below it.
    @MainActor
    private func expectNoBar(_ app: XCUIApplication, _ context: String) {
        let bar = app.navigationBars.firstMatch.frame
        let window = app.windows.firstMatch.frame
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "bar-scrolled-\(context)"
        shot.lifetime = .keepAlways
        add(shot)
        guard let image = screenshot.image.cgImage else { return XCTFail("\(context): no screenshot") }
        let pixels = Pixels(image)
        let scale = CGFloat(image.width) / window.width
        let x = Int(10 * scale)
        let reference = pixels[x, Int((bar.maxY + 12) * scale)]
        var worst = (difference: 0, y: 0)
        for y in Int(bar.midY * scale)...Int((bar.maxY + 3) * scale) {
            let difference = zip(pixels[x, y], reference).map { abs(Int($0) - Int($1)) }.max() ?? 0
            if difference > worst.difference { worst = (difference, y) }
        }
        print("[bar] \(context): bar \(bar) canvas \(reference) worst \(worst.difference) at y \(CGFloat(worst.y) / scale)")
        XCTAssertLessThanOrEqual(worst.difference, 8,
                                 "\(context): the scrolled bar draws its own background or hairline "
                                 + "(\(pixels[x, worst.y]) at y \(CGFloat(worst.y) / scale), canvas \(reference))")
    }
}

/// A screenshot's pixels as RGBA bytes.
private struct Pixels {
    private let bytes: [UInt8]
    private let width: Int

    init(_ image: CGImage) {
        width = image.width
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = data
    }

    subscript(x: Int, y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(bytes[i..<i + 3])
    }
}

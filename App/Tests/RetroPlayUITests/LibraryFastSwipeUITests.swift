// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Quick pulls down and pushes up, one after another before the last has settled (as a thumb
/// flicking up and down), leave the library's top where one slow pull would: the title and
/// its game count where they were at rest, one count, and the search field either away or
/// fully shown under the count with its placeholder; and in Cover Flow a fast push up after
/// a pull comes back to rest, five times over.
final class LibraryFastSwipeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private struct Top {
        var counts: [CGRect]
        var title: CGRect?
        var searchShows: Bool
        var search: CGRect
        var placeholder: String
        var shot: XCUIScreenshot
    }

    @MainActor
    private func top(_ app: XCUIApplication) -> Top {
        let counts = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ENDSWITH[c] %@", " games"))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.height > 0 }.map(\.frame)
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "RetroPlay"))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.height >= 40 }.first?.frame
        let field = app.searchFields.firstMatch
        let shows = field.exists && field.isHittable && field.frame.height > 20
        return Top(counts: counts, title: title, searchShows: shows, search: field.exists ? field.frame : .null,
                   placeholder: field.exists ? (field.placeholderValue ?? "") : "", shot: XCUIScreen.main.screenshot())
    }

    /// Waits for the top to hold still: the same count frames and search frame twice, 0.3 s apart.
    @MainActor
    private func settled(_ app: XCUIApplication) -> Top {
        var last = top(app)
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.3)
            let now = top(app)
            if now.counts == last.counts && now.search == last.search && now.title == last.title { return now }
            last = now
        }
        return last
    }

    @MainActor
    func testFastSwipesUpAndDownLeaveTheTopWhole() {
        for (name, layout, glitch) in [("coverFlow", "coverFlow", true), ("coverFlow-plain", "coverFlow", false),
                                       ("grid", "grid", true)] {
            let app = XCUIApplication()
            app.launchArguments = ["-retroplay.libraryLayout", layout] + (glitch ? [] : ["-RetroPlayTitleGlitchFrame", "-1"])
            app.launchRetroPlay()
            let settings = app.navigationBars.buttons["library.settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 30), "\(name): no library")
            XCTAssertTrue(waitFor("isHittable == true", settings, timeout: 10), "\(name): the bar didn't settle")
            Thread.sleep(forTimeInterval: 2)
            let rest = settled(app)
            print("[fast] \(name) rest: counts \(rest.counts) title \(String(describing: rest.title)) search \(rest.searchShows)")
            XCTAssertEqual(rest.counts.count, 1, "\(name): \(rest.counts.count) game counts at rest")
            XCTAssertFalse(rest.searchShows, "\(name): search shows at rest")

            let window = app.windows.firstMatch
            func flick(_ from: CGFloat, _ to: CGFloat, _ speed: CGFloat, hold: TimeInterval) {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                    .press(forDuration: 0.01,
                           thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                           withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: hold)
            }
            // Down and up, quicker and quicker, each before the last has come to rest; some
            // short (caught mid-reveal), some long.
            let flicks: [(CGFloat, CGFloat, CGFloat)] = [
                (0.35, 0.75, 2500), (0.75, 0.25, 2500), (0.4, 0.6, 4000), (0.6, 0.3, 4000),
                (0.35, 0.8, 5000), (0.8, 0.2, 5000), (0.45, 0.6, 6000), (0.6, 0.45, 6000),
                (0.35, 0.75, 3000), (0.75, 0.2, 6000), (0.4, 0.7, 6000), (0.7, 0.35, 3000),
            ]
            for (index, (from, to, speed)) in flicks.enumerated() {
                flick(from, to, speed, hold: index % 3 == 0 ? 0.05 : 0)
            }
            let after = settled(app)
            attachScreen("fastswipe-\(name)-after")
            print("[fast] \(name) after: counts \(after.counts) title \(String(describing: after.title)) search \(after.searchShows) \(after.search) “\(after.placeholder)”")
            check(name, after, against: rest)

            // A last fast pull down (search shown) and, in Cover Flow, a push up (back to rest).
            flick(0.35, 0.75, 5000, hold: 0)
            let shown = settled(app)
            attachScreen("fastswipe-\(name)-pulled")
            print("[fast] \(name) pulled: counts \(shown.counts) search \(shown.searchShows) \(shown.search) “\(shown.placeholder)”")
            check(name + " pulled", shown, against: rest)
            // A fast push collapses the bar at once; it comes back to rest every time, not
            // collapsed or pulled down.
            if layout == "coverFlow" {
                for round in 1...5 {
                    if round > 1 { flick(0.35, 0.75, 5000, hold: 0); _ = settled(app) }
                    flick(0.75, 0.25, 5000, hold: 0)
                    let back = settled(app)
                    print("[fast] \(name) back \(round): counts \(back.counts) search \(back.searchShows) \(back.search)")
                    if round == 1 { attachScreen("fastswipe-\(name)-back") }
                    check(name + " pushed back \(round)", back, against: rest)
                    XCTAssertFalse(back.searchShows, "\(name) \(round): a push up left search showing")
                }
            }
            app.terminate()
        }
    }

    /// The top as `rest` had it, or with the search field fully shown under the count.
    @MainActor
    private func check(_ name: String, _ now: Top, against rest: Top) {
        XCTAssertEqual(now.counts.count, 1, "\(name): \(now.counts.count) game counts: \(now.counts)")
        guard let count = now.counts.first, let restCount = rest.counts.first else { return }
        if now.searchShows {
            XCTAssertFalse(now.placeholder.isEmpty, "\(name): the search field shows without its placeholder")
            XCTAssertGreaterThanOrEqual(now.search.minY, count.maxY - 1, "\(name): the search field covers the count: \(now.search) vs \(count)")
            XCTAssertGreaterThanOrEqual(now.search.height, 36, "\(name): the search field is part way: \(now.search)")
            XCTAssertEqual(count.minY, restCount.minY, accuracy: 1, "\(name): the count moved with search showing: \(count) vs \(restCount)")
        } else {
            XCTAssertEqual(count.minY, restCount.minY, accuracy: 1, "\(name): the count isn't where it was at rest: \(count) vs \(restCount)")
            XCTAssertEqual(count.height, restCount.height, accuracy: 1, "\(name): the count's font changed: \(count) vs \(restCount)")
            if let title = now.title, let restTitle = rest.title {
                XCTAssertEqual(title.minY, restTitle.minY, accuracy: 1, "\(name): the title isn't where it was at rest")
            }
            // Drawn as at rest: the band from under the buttons to below the count (the plain
            // title holds still; the glitching one doesn't, so it's left to the frames).
            if rest.title != nil {
                let difference = Self.difference(now.shot.image, rest.shot.image, top: restCount.minY - 70, bottom: restCount.maxY + 30)
                XCTAssertLessThan(difference, 0.02, "\(name): the top isn't drawn as at rest (\(difference) of its pixels differ)")
            }
        }
    }

    /// The share of pixels (in points `top`…`bottom`, full width) that differ between two shots.
    private static func difference(_ a: UIImage, _ b: UIImage, top: CGFloat, bottom: CGFloat) -> Double {
        guard let ca = a.cgImage, let cb = b.cgImage, ca.width == cb.width, ca.height == cb.height else { return 1 }
        let scale = CGFloat(ca.width) / a.size.width
        let rect = CGRect(x: 0, y: max(0, top) * scale, width: CGFloat(ca.width), height: (bottom - max(0, top)) * scale).integral
        func pixels(_ image: CGImage) -> [UInt8] {
            guard let crop = image.cropping(to: rect) else { return [] }
            var data = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let context = CGContext(data: &data, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                    bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return data
        }
        let pa = pixels(ca), pb = pixels(cb)
        guard !pa.isEmpty, pa.count == pb.count else { return 1 }
        var differ = 0
        for i in stride(from: 0, to: pa.count, by: 4)
        where abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2])) > 60 {
            differ += 1
        }
        return Double(differ) / Double(pa.count / 4)
    }
}

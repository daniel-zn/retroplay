// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// Screenshots of the touch controls in landscape over a bright game and a darker one, in the
/// Liquid Glass and the flat style, for judging the controls' fixed opacity. Each extra
/// `-retroplay.padOpacity` value is only read by builds that still have the setting.
final class LandscapeControlsLookUITests: XCTestCase {
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLandscapeControlsOverBrightAndDarkGames() {
        let opacities = (ProcessInfo.processInfo.environment["RETROPLAY_PAD_OPACITIES"] ?? "")
            .split(separator: ",").map(String.init)
        for system in ["gba", "nes"] {
            for flat in [false, true] {
                for opacity in opacities.isEmpty ? [""] : opacities {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    let app = XCUIApplication()
                    app.launchArguments = ["-RetroPlaySmokeSystem", system, "-retroplay.flatControls", flat ? "YES" : "NO"]
                    if !opacity.isEmpty { app.launchArguments += ["-retroplay.padOpacity", opacity] }
                    app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
                    app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
                    app.launch()
                    // The game runs a few seconds so there's a picture behind the controls.
                    Thread.sleep(forTimeInterval: 9)
                    let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    shot.name = "controls-\(system)-\(flat ? "flat" : "glass")\(opacity.isEmpty ? "" : "-\(opacity)")"
                    shot.lifetime = .keepAlways
                    add(shot)
                    app.terminate()
                }
            }
        }
    }
}

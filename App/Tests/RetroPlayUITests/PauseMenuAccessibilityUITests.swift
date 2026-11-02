// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// With the pause menu open, VoiceOver reaches only the menu: not the game screen, the touch
/// controls or fast-forward / pause / sound behind it. Judged by the app's own walk of the
/// window as VoiceOver does it (`AccessibilityProbe`, debug builds): XCUITest's tree lists
/// elements that are hidden from VoiceOver.
final class PauseMenuAccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Launches the NES smoke game with the probe, the pause menu opened or not, and returns
    /// what VoiceOver can reach (lowercased), or nil if the probe didn't report.
    @MainActor
    private func reachable(_ app: XCUIApplication, menu: Bool, _ name: String) -> [String]? {
        app.launchArguments = ["-RetroPlaySmokeSystem", "nes", "-RetroPlaySmokeMenu", menu ? "YES" : "NO",
                               "-RetroPlaySmokeAccessibilityProbe", "YES",
                               // The touch controls are shown (the Simulator's keyboard counts as a controller).
                               "-retroplay.touchWithController", "YES"]
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        let probe = app.descendants(matching: .any)["a11y.probe"].firstMatch
        let ready = NSPredicate(format: "label BEGINSWITH[c] %@", "PROBE|")
        guard XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: ready, object: probe)], timeout: 60) == .completed else {
            XCTFail("\(name): the accessibility probe didn't report")
            return nil
        }
        let labels = probe.label.split(separator: "|").dropFirst().map { $0.lowercased() }
        let note = XCTAttachment(string: labels.joined(separator: "\n"))
        note.name = "pause-accessibility-\(name)-reachable"
        note.lifetime = .keepAlways
        add(note)
        return labels
    }

    /// The game's controls and screen, as the probe names them.
    private let behind: [(String, (String) -> Bool)] = [
        ("the game screen", { $0.hasSuffix(" screen") }),
        ("fast-forward", { $0.hasPrefix("fast forward") }),
        ("the pause button", { $0 == "pause menu" }),
        ("sound", { $0.hasPrefix("sound") }),
        ("the D-pad", { $0 == "d-pad" }),
        ("A", { $0 == "a" }),
        ("B", { $0 == "b" }),
        ("SELECT", { $0 == "select" }),
        ("START", { $0 == "start" }),
    ]

    /// The probe itself: with no menu open it does reach the game and its controls.
    @MainActor
    func testWithoutTheMenuTheGameAndControlsAreReachable() {
        let app = XCUIApplication()
        defer { app.terminate() }
        guard let labels = reachable(app, menu: false, "no-menu") else { return }
        for (what, matches) in behind {
            XCTAssertTrue(labels.contains(where: matches), "without the menu, VoiceOver doesn't reach \(what): \(labels)")
        }
    }

    @MainActor
    private func check(_ orientation: UIDeviceOrientation, _ name: String) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        defer { app.terminate() }
        guard let labels = reachable(app, menu: true, name) else { return }
        XCTAssertTrue(labels.contains { $0.hasPrefix("resume") }, "\(name): the menu isn't reachable: \(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("saves") }, "\(name): Saves isn't reachable: \(labels)")
        for (what, matches) in behind {
            XCTAssertFalse(labels.contains(where: matches), "\(name): VoiceOver reaches \(what) behind the open menu")
        }
    }

    @MainActor
    func testOnlyTheMenuIsReachableInPortrait() {
        check(.portrait, "portrait")
    }

    @MainActor
    func testOnlyTheMenuIsReachableInLandscape() {
        check(.landscapeLeft, "landscape")
    }
}

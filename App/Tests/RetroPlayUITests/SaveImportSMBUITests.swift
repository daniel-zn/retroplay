// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import UIKit

/// Picks a save folder on an SMB share through Files, the way a player with a NAS does: a
/// File Provider location, unlike the Simulator's own folders. Runs only when the test runner
/// is given a share (RETROPLAY_SMB_SERVER, _USER, _PASSWORD, _FOLDER: the path of folder names
/// under the share to open); skipped otherwise. Reads only.
final class SaveImportSMBUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The first button, cell or text labelled `label` (or starting with it).
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        // A fresh predicate per query: one handed to several would be shared across them.
        func labelled() -> NSPredicate {
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR identifier == %@", label, label, label)
        }
        for query in [app.buttons, app.cells, app.staticTexts, app.textFields, app.otherElements] {
            let match = query.matching(labelled()).firstMatch
            if match.exists { return match }
        }
        return app.buttons.matching(labelled()).firstMatch
    }

    private func tap(_ app: XCUIApplication, _ labels: [String], step: String, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let target = element(app, label)
                if target.exists, target.isHittable {
                    target.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        attach(app, "smb-stuck-\(step)")
        throw XCTSkip("Couldn't find \(labels) at step “\(step)”; see the attached screenshot.")
    }

    /// Disconnects the server in Files (its context menu in Browse), best effort.
    @MainActor
    private func forgetServer(_ server: String) {
        UIPasteboard.general.string = ""
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        let browse = element(files, "Browse")
        if browse.waitForExistence(timeout: 10) { browse.tap() }
        let entry = element(files, server)
        guard entry.waitForExistence(timeout: 10) else {
            attach(files, "smb-forget-no-server")
            files.terminate()
            return
        }
        entry.press(forDuration: 1.2)
        for label in ["Disconnect", "Eject", "Remove", "Forget"] {
            let action = element(files, label)
            if action.waitForExistence(timeout: 2) {
                action.tap()
                break
            }
        }
        attach(files, "smb-after-forget")
        files.terminate()
    }

    @MainActor
    func testPickingASaveFolderOnAnSMBShare() throws {
        guard let server = env["RETROPLAY_SMB_SERVER"], let user = env["RETROPLAY_SMB_USER"],
              let password = env["RETROPLAY_SMB_PASSWORD"], let folder = env["RETROPLAY_SMB_FOLDER"] else {
            throw XCTSkip("No SMB share given to the test runner.")
        }
        let path = folder.split(separator: "/").map(String.init)
        // Pass or skip, the Simulator doesn't keep the server afterwards (the job script also
        // resets its keychain).
        defer { forgetServer(server) }

        // 1. Files: connect to the server (kept for the picker afterwards).
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        try tap(files, ["Browse"], step: "files-browse", timeout: 20)
        if !element(files, server).waitForExistence(timeout: 3) {
            try tap(files, ["More", "More Options", "ellipsis", "ellipsis.circle"], step: "files-more")
            try tap(files, ["Connect to Server"], step: "files-connect-menu")
            let address = files.textFields.firstMatch
            guard address.waitForExistence(timeout: 10) else {
                attach(files, "smb-stuck-address")
                throw XCTSkip("No server address field.")
            }
            address.tap()
            address.typeText("smb://\(server)")
            try tap(files, ["Connect"], step: "files-connect")
            // The sign-in screen is up once it shows a password field.
            let secret = files.secureTextFields.firstMatch
            guard secret.waitForExistence(timeout: 20) else {
                attach(files, "smb-stuck-sign-in")
                throw XCTSkip("No sign-in screen after Connect.")
            }
            let registered = element(files, "Registered User")
            if registered.exists, registered.isHittable { registered.tap() }
            attach(files, "smb-sign-in")
            let name = files.textFields
                .matching(NSPredicate(format: "identifier != %@", "ServerAddressTextField"))
                .firstMatch
            guard name.waitForExistence(timeout: 5) else {
                attach(files, "smb-stuck-name")
                throw XCTSkip("No name field on the sign-in screen.")
            }
            name.tap()
            // It may come filled in (the device's owner): replace it.
            if let current = name.value as? String, !current.isEmpty, current != name.placeholderValue {
                name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            name.typeText(user)
            // Pasted, not typed: XCUITest logs typed text, and the password mustn't be logged.
            UIPasteboard.general.string = password
            defer { UIPasteboard.general.string = "" }
            secret.tap()
            secret.press(forDuration: 1.2)
            try tap(files, ["Paste"], step: "files-paste-password", timeout: 5)
            if files.buttons["Allow Paste"].waitForExistence(timeout: 3) { files.buttons["Allow Paste"].tap() }
            UIPasteboard.general.string = ""
            try tap(files, ["Next", "Connect", "Done"], step: "files-sign-in")
            _ = element(files, path.first ?? server).waitForExistence(timeout: 20)
        }
        attach(files, "smb-files-connected")
        files.terminate()

        // 2. RetroPlay: + → Saves, then the share's folder, then Open.
        let app = XCUIApplication()
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()
        try tap(app, ["library.import"], step: "plus", timeout: 30)
        try tap(app, ["library.import.saves", "Saves"], step: "saves")
        try tap(app, ["Browse"], step: "picker-browse", timeout: 20)
        try tap(app, [server], step: "picker-server", timeout: 20)
        for name in path {
            try tap(app, [name], step: "picker-\(name)", timeout: 20)
        }
        attach(app, "smb-picker-folder")
        try tap(app, ["Open"], step: "picker-open")

        // 3. What the scan made of it: a summary sheet or the "No saves" alert, with its notes.
        let summary = app.staticTexts["saveImport.summary"].firstMatch
        let found = summary.waitForExistence(timeout: 60)
        attach(app, "smb-result")
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        let note = XCTAttachment(string: texts.joined(separator: "\n"))
        note.name = "smb-result-texts"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(found, "No summary: the scan found nothing in the share's folder. Texts: \(texts)")
    }
}

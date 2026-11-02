// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The whole save import through the real Files picker, as a player does it: + → Saves →
/// Browse → On My iPhone → a folder → Open, then the summary and the import. "On My iPhone" is
/// Files' own File Provider (unlike the app's folders), so this is the path a NAS or iCloud
/// pick takes too.
///
/// Opt-in: the job that runs it puts the save folders in On My iPhone and the games in the
/// library, and tells the test runner what to pick and expect:
/// - RETROPLAY_FILES_ONE: a folder path under On My iPhone holding one save;
///   RETROPLAY_FILES_ONE_EXPECT: texts, joined with "|", its summary must show (e.g. the save's
///   folder name and "Found 1 save for 1 game", which only appears when it matched a game).
/// - RETROPLAY_FILES_ALL: a folder holding several; RETROPLAY_FILES_ALL_EXPECT: texts, joined
///   with "|", its summary must show. Those saves are then imported.
final class FilesPickerSaveImportUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        func labelled() -> NSPredicate {
            NSPredicate(format: "label ==[c] %@ OR identifier == %@", label, label)
        }
        for query in [app.cells, app.buttons, app.staticTexts] {
            let match = query.matching(labelled()).firstMatch
            if match.exists { return match }
        }
        return app.cells.matching(labelled()).firstMatch
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ label: String, step: String, timeout: TimeInterval = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let target = element(app, label)
            if target.exists, target.isHittable {
                target.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        attach(app, "files-stuck-\(step)")
        XCTFail("Couldn't find “\(label)” at step \(step)")
    }

    /// Opens a folder in the picker: taps it until the picker's title is that folder (a tap
    /// while the previous folder is still sliding in is lost).
    @MainActor
    private func open(_ app: XCUIApplication, _ folder: String) {
        // The picker's title is a button with a menu chevron, not plain text.
        func titled() -> Bool {
            app.navigationBars.descendants(matching: .any)
                .matching(NSPredicate(format: "label ==[c] %@ OR label BEGINSWITH[c] %@", folder, folder + ","))
                .firstMatch.exists
                || app.navigationBars[folder].exists
        }
        for attempt in 1...4 {
            if titled() { return }
            let item = app.cells.matching(NSPredicate(format: "label BEGINSWITH[c] %@", folder)).firstMatch
            let target = item.exists ? item : element(app, folder)
            if target.waitForExistence(timeout: 10), target.isHittable { target.tap() }
            let deadline = Date().addingTimeInterval(Double(attempt) * 2)
            while Date() < deadline, !titled() { Thread.sleep(forTimeInterval: 0.3) }
        }
        if !titled() {
            attach(app, "files-stuck-folder-\(folder)")
            XCTFail("Couldn't open “\(folder)” in the picker")
        }
    }

    /// Something on screen whose label contains `text` (summary rows combine their texts).
    @MainActor
    private func shows(_ app: XCUIApplication, _ text: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch.exists
    }

    /// + → Saves → Browse → On My iPhone → `path` → Open, then waits for the summary.
    @MainActor
    private func pick(_ app: XCUIApplication, _ path: String, name: String) {
        tap(app, "library.import", step: "plus", timeout: 30)
        tap(app, "Saves", step: "saves")
        // Browse twice: the first opens the tab, the second goes back to its locations.
        tap(app, "Browse", step: "browse", timeout: 20)
        tap(app, "Browse", step: "browse-root")
        tap(app, "On My iPhone", step: "on-my-iphone")
        for folder in path.split(separator: "/").map(String.init) {
            open(app, folder)
        }
        attach(app, "files-picker-\(name)")
        tap(app, "Open", step: "open")
        let summary = app.staticTexts["saveImport.summary"].firstMatch
        let found = summary.waitForExistence(timeout: 120)
        attach(app, "files-summary-\(name)")
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        let note = XCTAttachment(string: texts.joined(separator: "\n"))
        note.name = "files-summary-\(name)-texts"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(found, "No summary for \(path) (the “No saves” alert?): \(texts)")
    }

    @MainActor
    func testImportingSavesPickedInOnMyIPhone() throws {
        guard let one = env["RETROPLAY_FILES_ONE"], let oneExpect = env["RETROPLAY_FILES_ONE_EXPECT"],
              let all = env["RETROPLAY_FILES_ALL"], let allExpect = env["RETROPLAY_FILES_ALL_EXPECT"] else {
            throw XCTSkip("No On My iPhone folders given to the test runner.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()

        // The folder holding one save, exactly like the player: it's listed, nothing written.
        pick(app, one, name: "one")
        for text in oneExpect.split(separator: "|").map(String.init) {
            XCTAssertTrue(shows(app, text), "\(one): no “\(text)” in the summary")
        }
        // Closed the way a player does: dragged down by its grabber.
        let summary = app.staticTexts["saveImport.summary"].firstMatch
        for _ in 1...3 where summary.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline, summary.exists { Thread.sleep(forTimeInterval: 0.3) }
        }
        XCTAssertFalse(summary.exists, "the summary didn't close")

        // Their parent: every save under it, then imported.
        pick(app, all, name: "all")
        for text in allExpect.split(separator: "|").map(String.init) {
            XCTAssertTrue(shows(app, text), "\(all): no “\(text)” in the summary")
        }
        tap(app, "saveImport.import", step: "import")
        let done = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Imported")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 60), "no “Imported …” notice")
        attach(app, "files-imported")
    }

    /// One folder holding a save, opened and picked with Open (the folder picker takes one
    /// folder), then a folder inside RetroPlay's own folder in On My iPhone (the app's
    /// Documents, which needs no security-scoped access). Opt-in like the test above:
    /// - RETROPLAY_ONE_FOLDER: a folder path under On My iPhone; RETROPLAY_ONE_FOLDER_EXPECT:
    ///   texts, joined with "|", its summary must show.
    /// - RETROPLAY_OWN_FOLDER: a folder path under On My iPhone → RetroPlay; RETROPLAY_OWN_EXPECT.
    @MainActor
    func testPickingOneFolderAndOneInTheAppsOwnFolder() throws {
        guard let one = env["RETROPLAY_ONE_FOLDER"], let expect = env["RETROPLAY_ONE_FOLDER_EXPECT"] else {
            throw XCTSkip("No On My iPhone folders given to the test runner.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = ""
        app.launchEnvironment["DYLD_LIBRARY_PATH"] = ""
        app.launch()

        pick(app, one, name: "one-folder")
        for text in expect.split(separator: "|").map(String.init) {
            XCTAssertTrue(shows(app, text), "\(one): no “\(text)” in the summary")
        }
        closeSummary(app)

        if let own = env["RETROPLAY_OWN_FOLDER"], let ownExpect = env["RETROPLAY_OWN_EXPECT"] {
            pick(app, "RetroPlay/" + own, name: "own")
            for text in ownExpect.split(separator: "|").map(String.init) {
                XCTAssertTrue(shows(app, text), "\(own): no “\(text)” in the summary")
            }
            closeSummary(app)
        }
    }

    @MainActor
    private func closeSummary(_ app: XCUIApplication) {
        let summary = app.staticTexts["saveImport.summary"].firstMatch
        for _ in 1...3 where summary.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline, summary.exists { Thread.sleep(forTimeInterval: 0.3) }
        }
        XCTAssertFalse(summary.exists, "the summary didn't close")
    }
}

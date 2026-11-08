// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class AutoResumeLoaderTests: XCTestCase {
    // MARK: - Pure decision logic

    func testDecisionIsFirstRunWhenNoQuickSaveExists() {
        XCTAssertEqual(
            AutoResumeLoader.decide(hasSaveHistory: false, supportsSaveState: true),
            .firstRun
        )
    }

    func testDecisionIsFirstRunWhenCoreDoesNotSupportSaveState() {
        XCTAssertEqual(
            AutoResumeLoader.decide(hasSaveHistory: true, supportsSaveState: false),
            .firstRun
        )
    }

    func testDecisionIsAttemptLoadWhenQuickSaveExistsAndSupported() {
        XCTAssertEqual(
            AutoResumeLoader.decide(hasSaveHistory: true, supportsSaveState: true),
            .attemptLoad
        )
    }

    func testStatusLinesNeverImplyATrapOrCrash() {
        XCTAssertEqual(AutoResumeLoader.statusLine(for: .loaded), "Resumed from quick save")
        XCTAssertEqual(AutoResumeLoader.statusLine(for: .firstRun), "Waiting for first frame…")
        XCTAssertEqual(AutoResumeLoader.statusLine(for: .failed), "Auto-load failed — starting fresh")
        XCTAssertEqual(AutoResumeLoader.statusLine(for: .cancelled), "Waiting for first frame…")
    }

    // MARK: - End-to-end `apply` against a fake core + real SavePaths sandbox

    func testApplySkipsLoadWhenQuickSaveIsMissing() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let core = RecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: UUID(),
            paths: paths
        )

        XCTAssertEqual(status, .firstRun)
        XCTAssertFalse(core.loadStateCalled)
    }

    func testApplyLoadsWhenQuickSaveExists() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("fake-state".utf8).write(to: quickURL)

        let core = RecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertEqual(core.loadStateURL, quickURL)
        XCTAssertTrue(core.pauseCalled)
        XCTAssertTrue(core.resumeCalled)
    }

    func testApplyReportsFailureWithoutTrappingWhenLoadThrows() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("fake-state".utf8).write(to: quickURL)

        let core = RecordingCore()
        core.loadStateError = EmulatorCoreError.romLoadFailed("corrupt state")
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .failed)
        // Even on failure, the core must be left running (resumed), never stuck paused.
        XCTAssertTrue(core.resumeCalled)
    }

    func testApplyLoadsOldestRemainingSlotWhenLatestMissing() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        for value in ["older", "newest"] {
            let staged = try SaveStateStore.stagingSaveURL(system: .gba, gameID: gameID, paths: paths)
            try Data(value.utf8).write(to: staged)
            try SaveStateStore.commitStagedQuickSave(staged, system: .gba, gameID: gameID, paths: paths)
        }
        let latest = try SaveStateStore.quickSaveURL(
            system: .gba,
            gameID: gameID,
            paths: paths,
            createDirectory: false
        )
        try FileManager.default.removeItem(at: latest)

        let core = RecordingCore(systemID: .gba)
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .gba,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(core.loadStateURL), encoding: .utf8), "older")
    }

    func testApplyDoesNotResumeWhenResumeAfterLoadIsFalse() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("fake-state".utf8).write(to: quickURL)

        let core = RecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths,
            resumeAfterLoad: false
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertFalse(core.resumeCalled)
    }

    func testApplyFallsBackToOlderSlotWhenLatestSaveIsCorrupt() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        for value in ["older", "corrupt"] {
            let staged = try SaveStateStore.stagingSaveURL(system: .gba, gameID: gameID, paths: paths)
            try Data(value.utf8).write(to: staged)
            try SaveStateStore.commitStagedQuickSave(staged, system: .gba, gameID: gameID, paths: paths)
        }

        let core = RecordingCore(systemID: .gba)
        core.loadStateErrorsByPath = { url in
            (try? String(contentsOf: url, encoding: .utf8)) == "corrupt"
                ? EmulatorCoreError.romLoadFailed("corrupt state")
                : nil
        }

        let status = await AutoResumeLoader.apply(
            core: core,
            system: .gba,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(core.loadStateURL), encoding: .utf8), "older")
        let latest = try SaveStateStore.quickSaveURL(
            system: .gba,
            gameID: gameID,
            paths: paths,
            createDirectory: false
        )
        // The unloadable slot is kept, never deleted behind the user's back.
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
    }

    func testApplyPrefersPendingQuickSaveOverOlderCommittedSlot() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let committed = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("committed".utf8).write(to: committed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: committed.path
        )

        let pending = try SaveStateStore.stagingSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("pending".utf8).write(to: pending)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: pending.path
        )

        let core = RecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(core.loadStateURL), encoding: .utf8), "pending")
    }

    func testApplyAbortsBeforeAttemptingLoadWhenAlreadyStale() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("fake-state".utf8).write(to: quickURL)

        let core = RecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths,
            resumeAfterLoad: false,
            shouldContinue: { false }
        )

        XCTAssertEqual(status, .cancelled)
        XCTAssertFalse(core.loadStateCalled)
        XCTAssertTrue(core.pauseCalled)
        XCTAssertFalse(core.resumeCalled)
    }

    func testApplySkipsWhenCoreDoesNotSupportSaveStateEvenIfQuickSaveExists() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("fake-state".utf8).write(to: quickURL)

        let core = RecordingCore()
        core.supportsSaveState = false
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(status, .firstRun)
        XCTAssertFalse(core.loadStateCalled)
    }

    // MARK: - Helpers

    private func makeSandboxPaths() throws -> (SavePaths, () -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-autoresume-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = SavePaths(fileManager: fm, documentsURL: root)
        return (paths, { try? fm.removeItem(at: root) })
    }
}

private final class RecordingCore: TestEmulatorCore, @unchecked Sendable {
    let systemID: SystemID
    let coreName = "RecordingCore"
    var supportsSaveState = true
    var supportsFastForward = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var loadStateCalled = false
    private(set) var loadStateURL: URL?
    var loadStateError: Error?

    init(systemID: SystemID = .psp) {
        self.systemID = systemID
    }
    func start() {}
    func pause() { pauseCalled = true }
    func resume() { resumeCalled = true }
    func stop() {}
    func saveState(to url: URL) async throws {}
    func loadState(from url: URL) async throws {
        loadStateCalled = true
        loadStateURL = url
        if let pathError = loadStateErrorsByPath?(url) {
            throw pathError
        }
        if let loadStateError { throw loadStateError }
    }

    var loadStateErrorsByPath: ((URL) -> Error?)?
    func setFastForward(_ enabled: Bool) {}
}


// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class SaveStateHistoryTests: XCTestCase {
    func testEntriesAreNewestFirstAndLimitedToFive() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()

        for number in 1...6 {
            let staged = try SaveStateStore.stagingSaveURL(
                system: .gba,
                gameID: gameID,
                paths: paths
            )
            try Data("save-\(number)".utf8).write(to: staged)
            try SaveStateStore.commitStagedQuickSave(
                staged,
                system: .gba,
                gameID: gameID,
                paths: paths
            )
        }

        let entries = SaveStateStore.entries(system: .gba, gameID: gameID, paths: paths)
        XCTAssertEqual(entries.map(\.slot), [0, 1, 2, 3, 4])
        XCTAssertEqual(entries.count, SaveStateStore.maximumSaveCount)
        XCTAssertEqual(try entries.map { try String(contentsOf: $0.url, encoding: .utf8) }, [
            "save-6", "save-5", "save-4", "save-3", "save-2"
        ])
    }

    func testEntriesSkipMissingFilesDeterministically() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()

        for value in ["older", "newest"] {
            let staged = try SaveStateStore.stagingSaveURL(
                system: .nds,
                gameID: gameID,
                paths: paths
            )
            try Data(value.utf8).write(to: staged)
            try SaveStateStore.commitStagedQuickSave(
                staged,
                system: .nds,
                gameID: gameID,
                paths: paths
            )
        }

        let latest = try SaveStateStore.quickSaveURL(
            system: .nds,
            gameID: gameID,
            paths: paths,
            createDirectory: false
        )
        try FileManager.default.removeItem(at: latest)

        let entries = SaveStateStore.entries(system: .nds, gameID: gameID, paths: paths)
        XCTAssertEqual(entries.map(\.slot), [1])
        XCTAssertEqual(try String(contentsOf: entries[0].url, encoding: .utf8), "older")
        XCTAssertFalse(SaveStateStore.quickSaveExists(system: .nds, gameID: gameID, paths: paths))
    }

    func testResolvedEntriesPreferNewerPendingQuickSave() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()

        let committed = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("committed".utf8).write(to: committed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: committed.path
        )

        let pending = try SaveStateStore.stagingSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("pending".utf8).write(to: pending)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: pending.path
        )

        let entries = SaveStateStore.resolvedEntries(system: .gba, gameID: gameID, paths: paths)
        XCTAssertEqual(try String(contentsOf: entries[0].url, encoding: .utf8), "pending")
        XCTAssertEqual(entries[0].slot, 0)
    }

    func testNewestEntryFallsBackToOldestSlotWhenLatestMissing() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()

        for value in ["older", "newest"] {
            let staged = try SaveStateStore.stagingSaveURL(
                system: .gba,
                gameID: gameID,
                paths: paths
            )
            try Data(value.utf8).write(to: staged)
            try SaveStateStore.commitStagedQuickSave(
                staged,
                system: .gba,
                gameID: gameID,
                paths: paths
            )
        }

        let latest = try SaveStateStore.quickSaveURL(
            system: .gba,
            gameID: gameID,
            paths: paths,
            createDirectory: false
        )
        try FileManager.default.removeItem(at: latest)

        let entry = SaveStateStore.newestEntry(system: .gba, gameID: gameID, paths: paths)
        XCTAssertEqual(entry?.slot, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(entry?.url), encoding: .utf8), "older")
        XCTAssertTrue(SaveStateStore.anySaveExists(system: .gba, gameID: gameID, paths: paths))
        XCTAssertFalse(SaveStateStore.quickSaveExists(system: .gba, gameID: gameID, paths: paths))
    }

    func testCommitRejectsMissingStagedFileWithoutDeletingCurrentSave() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let current = try SaveStateStore.quickSaveURL(system: .n64, gameID: gameID, paths: paths)
        try Data("current".utf8).write(to: current)
        let missing = current.deletingLastPathComponent().appendingPathComponent("missing.state")

        XCTAssertThrowsError(
            try SaveStateStore.commitStagedQuickSave(
                missing,
                system: .n64,
                gameID: gameID,
                paths: paths
            )
        )
        XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "current")
    }

    @MainActor
    func testSelectedLoadTreatsMissingFileAsSafeNoOp() async {
        let core = RestartRecordingCore()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-missing-\(UUID().uuidString).state")

        let result = await SaveStateLoader.apply(
            core: core,
            url: missing,
            resumeAfterLoad: true
        )

        XCTAssertEqual(result, .missing)
        XCTAssertFalse(core.pauseCalled)
        XCTAssertFalse(core.loadStateCalled)
        XCTAssertFalse(core.resumeCalled)
    }

    @MainActor
    func testSelectedLoadReportsCorruptSaveAndResumesRunningCore() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let corrupt = paths.statesDirectory.appendingPathComponent("corrupt.state")
        try FileManager.default.createDirectory(
            at: corrupt.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-valid-state".utf8).write(to: corrupt)
        let core = RestartRecordingCore()
        core.loadStateError = EmulatorCoreError.romLoadFailed("corrupt state")

        let result = await SaveStateLoader.apply(
            core: core,
            url: corrupt,
            resumeAfterLoad: true
        )

        XCTAssertEqual(result, .failed("corrupt state"))
        XCTAssertTrue(core.pauseCalled)
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertTrue(core.resumeCalled)
    }

    @MainActor
    func testPSPRestartStopsCoreClearsSavesAndRequiresFreshBoot() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = RestartRecordingCore(systemID: .psp)

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(outcome, .ready)
        XCTAssertTrue(outcome.shouldBootFresh)
        XCTAssertTrue(core.stopCalled)
        XCTAssertTrue(SaveStateStore.entries(system: .psp, gameID: gameID, paths: paths).isEmpty)
    }

    @MainActor
    func testGBARestartStopsCoreClearsSavesAndRequiresFreshBoot() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = RestartRecordingCore(systemID: .gba)

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: .gba,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(outcome, .ready)
        XCTAssertTrue(outcome.shouldBootFresh)
        XCTAssertTrue(core.stopCalled)
        XCTAssertTrue(SaveStateStore.entries(system: .gba, gameID: gameID, paths: paths).isEmpty)
    }

    @MainActor
    func testRestartCleanupFailureKeepsCurrentCorePausedAndDoesNotBootFresh() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = RestartRecordingCore(systemID: .gba)

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: .gba,
            gameID: gameID,
            paths: paths,
            fileManager: RemoveFailingFileManager()
        )

        XCTAssertEqual(outcome, .saveCleanupFailed)
        XCTAssertFalse(outcome.shouldBootFresh)
        XCTAssertFalse(core.stopCalled)
        XCTAssertTrue(core.pauseCalled)
        // The pause menu is still open; closing it resumes the game.
        XCTAssertFalse(core.resumeCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quick.path))
    }

    @MainActor
    func testRestartPausesCoreBeforeDeletingSaves() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = RestartRecordingCore(systemID: .psp)

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: .psp,
            gameID: gameID,
            paths: paths
        )

        XCTAssertEqual(outcome, .ready)
        XCTAssertTrue(core.pauseCalled)
        XCTAssertTrue(core.stopCalled)
    }

    @MainActor
    func testRestartDecisionIgnoresBusyAndMissingCore() {
        XCTAssertEqual(
            RestartFromScratch.decide(hasActiveCore: true, operationInProgress: true),
            .ignoreOperationInProgress
        )
        XCTAssertEqual(
            RestartFromScratch.decide(hasActiveCore: false, operationInProgress: false),
            .ignoreNoActiveCore
        )
        XCTAssertEqual(
            RestartFromScratch.decide(hasActiveCore: true, operationInProgress: false),
            .restart
        )
    }

    func testDiscardPendingQuickSaveStopsFailedWriteFromShadowingCommittedSlot() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()

        let committed = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("good".utf8).write(to: committed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: committed.path
        )

        let pending = try SaveStateStore.stagingSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("partial".utf8).write(to: pending)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: pending.path
        )

        XCTAssertEqual(
            SaveStateStore.resolvedEntries(system: .gba, gameID: gameID, paths: paths).first?.url,
            pending
        )

        SaveStateStore.discardPendingQuickSave(system: .gba, gameID: gameID, paths: paths)

        let entries = SaveStateStore.resolvedEntries(system: .gba, gameID: gameID, paths: paths)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].slot, 0)
        XCTAssertEqual(entries[0].url, committed)
        XCTAssertEqual(try String(contentsOf: committed, encoding: .utf8), "good")
    }

    func testPlaybackControlStateAlternatesPauseAndResume() {
        var state = PlaybackControlState.running
        XCTAssertEqual(state.action, .pause)
        XCTAssertEqual(state.accessibilityLabel, "Pause")
        XCTAssertEqual(state.statusLine, "Running")

        state.toggle()
        XCTAssertEqual(state, .paused)
        XCTAssertEqual(state.action, .resume)
        XCTAssertEqual(state.accessibilityLabel, "Resume")
        XCTAssertEqual(state.statusLine, "Paused")
    }

    private func makeSandboxPaths() throws -> (SavePaths, () -> Void) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("rp-state-history-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            SavePaths(fileManager: fileManager, documentsURL: root),
            { try? fileManager.removeItem(at: root) }
        )
    }
}

private final class RestartRecordingCore: TestEmulatorCore, @unchecked Sendable {
    let systemID: SystemID
    let coreName = "RestartRecordingCore"
    var supportsSaveState = true
    var supportsFastForward = false
    private(set) var stopCalled = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var loadStateCalled = false
    var loadStateError: Error?

    init(systemID: SystemID = .psp) {
        self.systemID = systemID
    }
    func start() {}
    func pause() { pauseCalled = true }
    func resume() { resumeCalled = true }
    func stop() { stopCalled = true }
    func saveState(to url: URL) async throws {}
    func loadState(from url: URL) async throws {
        loadStateCalled = true
        if let loadStateError { throw loadStateError }
    }
    func setFastForward(_ enabled: Bool) {}
}

private final class RemoveFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

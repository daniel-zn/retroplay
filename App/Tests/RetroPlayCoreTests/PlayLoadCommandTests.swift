// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import XCTest
@testable import RetroPlayCore

final class PlayLoadCommandTests: XCTestCase {
    func testGateBlocksBusyQuickLoadAndRestart() {
        XCTAssertEqual(
            PlayLoadReducer.gate(
                for: .quickLoad,
                saveBusy: true,
                hasCore: true,
                supportsSaveState: true,
                hasSaveHistory: true
            ),
            .ignoreBusy
        )
        XCTAssertEqual(
            PlayLoadReducer.gate(
                for: .restartFromScratch,
                saveBusy: true,
                hasCore: true,
                supportsSaveState: true,
                hasSaveHistory: true
            ),
            .ignoreBusy
        )
        XCTAssertEqual(
            PlayLoadReducer.statusLine(for: .ignoreBusy),
            "Wait for save/load to finish"
        )
    }

    func testGateAllowsQuickLoadWhenOnlyOlderSlotRemains() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let dir = SaveStateStore.quickSaveDirectory(system: .nds, gameID: gameID, paths: paths)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let older = dir.appendingPathComponent("quick-1.state")
        try Data("older".utf8).write(to: older)
        let entries = SaveStateStore.entries(system: .nds, gameID: gameID, paths: paths)

        XCTAssertEqual(
            PlayLoadReducer.gate(
                for: .quickLoad,
                saveBusy: false,
                hasCore: true,
                supportsSaveState: true,
                hasSaveHistory: !entries.isEmpty
            ),
            .execute
        )
        XCTAssertEqual(PlayLoadReducer.entry(for: .quickLoad, entries: entries)?.slot, 1)
    }

    func testGateRequiresQuickSaveForTapLoad() {
        XCTAssertEqual(
            PlayLoadReducer.gate(
                for: .quickLoad,
                saveBusy: false,
                hasCore: true,
                supportsSaveState: true,
                hasSaveHistory: false
            ),
            .ignoreNoQuickSave
        )
    }

    func testGateAllowsQuickLoadWhenOnlyPendingQuickSaveExists() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let pending = try SaveStateStore.stagingSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("pending".utf8).write(to: pending)
        let entries = SaveStateStore.resolvedEntries(system: .psp, gameID: gameID, paths: paths)

        XCTAssertEqual(
            PlayLoadReducer.gate(
                for: .quickLoad,
                saveBusy: false,
                hasCore: true,
                supportsSaveState: true,
                hasSaveHistory: !entries.isEmpty
            ),
            .execute
        )
        XCTAssertEqual(PlayLoadReducer.entry(for: .quickLoad, entries: entries)?.url, pending)
    }

    func testEntrySelectionUsesLatestOrExplicitSlot() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        let older = latest.deletingLastPathComponent().appendingPathComponent("quick-1.state")
        try Data("older".utf8).write(to: older)
        let entries = SaveStateStore.entries(system: .gba, gameID: gameID, paths: paths)

        XCTAssertEqual(
            PlayLoadReducer.entry(for: .quickLoad, entries: entries)?.slot,
            0
        )
        XCTAssertEqual(
            PlayLoadReducer.entry(for: .loadEntry(entries[1]), entries: entries)?.slot,
            1
        )
    }

    @MainActor
    func testLoadSessionAppliesSelectedSaveIntoCore() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let saveURL = paths.statesDirectory
            .appendingPathComponent("gba", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("quick.state")
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("state".utf8).write(to: saveURL)
        let core = LoadRecordingCore()
        let entry = SaveStateStore.Entry(slot: 0, url: saveURL, modifiedAt: Date())

        let outcome = await PlayLoadSession.load(
            entry: entry,
            core: core,
            wasPaused: false
        )

        XCTAssertEqual(outcome, .loaded(statusLine: "Quick load OK"))
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertTrue(core.resumeCalled)
    }

    @MainActor
    func testLoadSessionDoesNotResumeWhileBackgroundPaused() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let saveURL = paths.statesDirectory
            .appendingPathComponent("gba", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("quick.state")
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("state".utf8).write(to: saveURL)
        let core = LoadRecordingCore()
        let entry = SaveStateStore.Entry(slot: 0, url: saveURL, modifiedAt: Date())

        let outcome = await PlayLoadSession.load(
            entry: entry,
            core: core,
            wasPaused: false,
            pausedForBackground: true
        )

        XCTAssertEqual(outcome, .loaded(statusLine: "Quick load OK"))
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertFalse(core.resumeCalled)
    }

    @MainActor
    func testLoadSessionReportsMissingSaveSafely() async {
        let core = LoadRecordingCore()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-missing-\(UUID().uuidString).state")
        let entry = SaveStateStore.Entry(slot: 2, url: missing, modifiedAt: nil)

        let outcome = await PlayLoadSession.load(
            entry: entry,
            core: core,
            wasPaused: true
        )

        XCTAssertEqual(outcome, .missing)
        XCTAssertFalse(core.loadStateCalled)
        XCTAssertFalse(core.pauseCalled)
    }

    @MainActor
    func testRestartCommandPreparesFreshBootAndClearsSaves() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .psp, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = LoadRecordingCore(systemID: .psp)

        let gate = PlayLoadReducer.gate(
            for: .restartFromScratch,
            saveBusy: false,
            hasCore: true,
            supportsSaveState: true,
            hasSaveHistory: true
        )
        XCTAssertEqual(gate, .execute)

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
    func testLoadActionCoordinatorDispatchesSelectedSaveCommand() async {
        let coordinator = PlayLoadActionCoordinator()
        let entry = SaveStateStore.Entry(
            slot: 1,
            url: URL(fileURLWithPath: "/tmp/quick-1.state"),
            modifiedAt: nil
        )
        var handled: [PlayLoadCommand] = []

        coordinator.submit(.loadEntry(entry)) { command in
            handled.append(command)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.submissionCount, 1)
        XCTAssertEqual(coordinator.lastSubmittedCommand, .loadEntry(entry))
        XCTAssertEqual(handled, [.loadEntry(entry)])
    }

    @MainActor
    func testLoadActionCoordinatorDispatchesRestartFromScratch() async {
        let coordinator = PlayLoadActionCoordinator()
        var handled: [PlayLoadCommand] = []

        coordinator.submit(.restartFromScratch) { command in
            handled.append(command)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.lastSubmittedCommand, .restartFromScratch)
        XCTAssertEqual(handled, [.restartFromScratch])
    }

    @MainActor
    func testLoadActionCoordinatorIgnoresSupersededInFlightCommand() async {
        let coordinator = PlayLoadActionCoordinator()
        var handled: [PlayLoadCommand] = []

        coordinator.submit(.quickLoad) { command in
            handled.append(command)
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            handled.append(.restartFromScratch)
        }
        coordinator.submit(.restartFromScratch) { command in
            handled.append(command)
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(handled, [.restartFromScratch])
    }

    @MainActor
    func testMenuActionLoadsTheSelectedSaveIntoTheActiveCore() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        let older = latest.deletingLastPathComponent().appendingPathComponent("quick-1.state")
        try Data("older".utf8).write(to: older)
        host.refresh()

        XCTAssertTrue(host.button.invokeMenuAction(
            identifier: PlayLoadMenuContent.entryIdentifier(slot: 1)
        ))
        await waitUntil { host.statusLine == "Loaded previous save 1" }

        XCTAssertEqual(host.coreRecorder.loadedURL, older)
        XCTAssertTrue(host.coreRecorder.loadStateCalled)
        XCTAssertEqual(host.alerts, [])
        XCTAssertFalse(host.saveBusy)
    }

    @MainActor
    func testPrimaryTapQuickLoadsLatestSave() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        host.refresh()

        host.button.invokePrimaryTap()
        await waitUntil { host.statusLine == "Quick load OK" }

        XCTAssertEqual(host.coreRecorder.loadedURL, latest)
        XCTAssertTrue(host.coreRecorder.loadStateCalled)
    }

    @MainActor
    func testRestartMenuActionStopsCoreClearsSavesAndBootsFresh() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths, system: .psp)
        let quick = try SaveStateStore.quickSaveURL(system: .psp, gameID: host.gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        host.refresh()

        XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier))
        await waitUntil { host.bootCount == 1 }

        XCTAssertTrue(host.coreRecorder.stopCalled)
        XCTAssertEqual(host.statusLine, "Restarting from scratch…")
        XCTAssertTrue(SaveStateStore.entries(system: .psp, gameID: host.gameID, paths: paths).isEmpty)
        XCTAssertFalse(host.saveBusy)
    }

    @MainActor
    func testMenuActionReportsMissingSaveWithoutTouchingTheCore() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        host.refresh()
        try FileManager.default.removeItem(at: latest)

        XCTAssertTrue(host.button.invokeMenuAction(
            identifier: PlayLoadMenuContent.entryIdentifier(slot: 0)
        ))
        await waitUntil { host.alerts.isEmpty == false }

        XCTAssertEqual(host.alerts, [PlayLoadReducer.missingSaveMessage()])
        XCTAssertEqual(host.statusLine, "Save load failed")
        XCTAssertFalse(host.coreRecorder.loadStateCalled)
        XCTAssertFalse(host.coreRecorder.pauseCalled)
    }

    @MainActor
    func testMenuActionReportsFailedLoadAndKeepsTheFile() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("corrupt".utf8).write(to: latest)
        host.refresh()
        host.coreRecorder.loadError = EmulatorCoreError.romLoadFailed("corrupt state")

        XCTAssertTrue(host.button.invokeMenuAction(
            identifier: PlayLoadMenuContent.entryIdentifier(slot: 0)
        ))
        await waitUntil { host.alerts.isEmpty == false }

        XCTAssertEqual(host.alerts, ["corrupt state"])
        XCTAssertEqual(host.statusLine, "Save load failed")
        XCTAssertTrue(host.coreRecorder.loadStateCalled)
        XCTAssertTrue(host.coreRecorder.resumeCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
        XCTAssertEqual(host.entries.map(\.slot), [0])
    }

    @MainActor
    func testRestartCleanupFailureLeavesCorePausedAndRunning() throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let gameID = UUID()
        let quick = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quick)
        let core = LoadRecordingCore(systemID: .gba)

        let outcome = RestartFromScratch.prepare(
            core: core,
            operationInProgress: false,
            system: .gba,
            gameID: gameID,
            paths: paths,
            fileManager: FailingRemoveFileManager()
        )

        XCTAssertEqual(outcome, .saveCleanupFailed)
        XCTAssertFalse(outcome.shouldBootFresh)
        XCTAssertTrue(core.pauseCalled)
        // The pause menu is still open; closing it is what resumes the game.
        XCTAssertFalse(core.resumeCalled)
        XCTAssertFalse(core.stopCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quick.path))
    }

    @MainActor
    func testRejectedMenuCommandsSetAVisibleStatus() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        host.core = nil

        XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier))
        await waitUntil { host.statusLine == "Game is not running" }
        XCTAssertEqual(host.bootCount, 0)
        XCTAssertFalse(host.coreRecorder.stopCalled)

        host.core = host.coreRecorder
        host.saveBusy = true
        host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier)
        await waitUntil { host.statusLine == "Wait for save/load to finish" }
        XCTAssertEqual(host.bootCount, 0)

        host.saveBusy = false
        host.button.invokePrimaryTap()
        await waitUntil { host.statusLine == "No save state yet" }

        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        host.coreRecorder.supportsSaveState = false
        host.button.invokePrimaryTap()
        await waitUntil { host.statusLine == "Save states not available" }
        XCTAssertFalse(host.coreRecorder.loadStateCalled)
    }

    @MainActor
    func testImportMenuActionIsSeparateFromLoad() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)

        XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.importIdentifier))
        XCTAssertTrue(host.imported)
        XCTAssertFalse(host.coreRecorder.loadStateCalled)
        XCTAssertEqual(host.bootCount, 0)
        XCTAssertEqual(host.statusLine, "")
    }

    @MainActor
    func testEmptySaveRowIsDisabledAndRestartStillRuns() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        host.refresh()

        XCTAssertEqual(
            host.button.menuActionAttributes(identifier: PlayLoadMenuContent.emptyIdentifier),
            .disabled
        )
        XCTAssertFalse(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.emptyIdentifier))
        XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier))
        await waitUntil { host.bootCount == 1 }
        XCTAssertTrue(host.coreRecorder.stopCalled)
    }

    @MainActor
    func testMenuRebuildDoesNotCancelAnAcceptedLoad() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        host.refresh()
        host.coreRecorder.holdNanoseconds = 250_000_000

        XCTAssertTrue(host.button.invokeMenuAction(
            identifier: PlayLoadMenuContent.entryIdentifier(slot: 0)
        ))
        await waitUntil { host.coreRecorder.loadStateCalled }
        var rebuilt = host.entries
        rebuilt.append(
            SaveStateStore.Entry(
                slot: 4,
                url: URL(fileURLWithPath: "/tmp/retroplay-rebuild-\(UUID().uuidString).state"),
                modifiedAt: nil
            )
        )
        host.button.setEntries(rebuilt)
        host.button.onCommand = { host.submit($0) }

        await waitUntil { host.statusLine == "Quick load OK" }
        XCTAssertEqual(host.coreRecorder.loadedURL, latest)
        XCTAssertEqual(host.coordinatorCancelCount, 0)
    }

    @MainActor
    func testCallerTaskCancellationDoesNotDropRestart() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        host.refresh()

        let parent = Task { @MainActor in
            XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier))
        }
        await parent.value
        parent.cancel()
        await waitUntil { host.bootCount == 1 }

        XCTAssertEqual(host.bootCount, 1)
        XCTAssertTrue(host.coreRecorder.stopCalled)
        XCTAssertEqual(host.statusLine, "Restarting from scratch…")
    }

    @MainActor
    func testSessionCancelAbandonsInFlightLoadWithoutReportingFailure() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        let latest = try SaveStateStore.quickSaveURL(system: .gba, gameID: host.gameID, paths: paths)
        try Data("latest".utf8).write(to: latest)
        host.refresh()
        host.coreRecorder.holdNanoseconds = 800_000_000

        XCTAssertTrue(host.button.invokeMenuAction(
            identifier: PlayLoadMenuContent.entryIdentifier(slot: 0)
        ))
        await waitUntil { host.coreRecorder.loadStateCalled }
        host.coordinator.cancel()
        host.coordinatorCancelCount += 1
        await waitUntil { host.saveBusy == false }

        XCTAssertNotEqual(host.statusLine, "Quick load OK")
        XCTAssertTrue(host.alerts.isEmpty)
        XCTAssertFalse(host.coreRecorder.resumeCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.path))
    }

    @MainActor
    func testSessionCancelAbandonsRestartBeforeBootCompletes() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let host = try makeHost(paths: paths)
        host.refresh()
        host.delayBoot = true

        XCTAssertTrue(host.button.invokeMenuAction(identifier: PlayLoadMenuContent.restartIdentifier))
        await waitUntil { host.bootStarted }
        host.coordinator.cancel()
        await waitUntil { host.saveBusy == false }

        XCTAssertEqual(host.bootCount, 0)
        XCTAssertTrue(host.coreRecorder.stopCalled)
    }

    @MainActor
    func testCancelledSaveLoadIsNotReportedAsCorrupt() async throws {
        let (paths, cleanup) = try makeSandboxPaths()
        defer { cleanup() }
        let saveURL = paths.statesDirectory.appendingPathComponent("gba-cancel.state")
        try FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("state".utf8).write(to: saveURL)
        let core = LoadRecordingCore()
        core.holdNanoseconds = 400_000_000
        let task = Task { @MainActor in
            await SaveStateLoader.apply(core: core, url: saveURL, resumeAfterLoad: true)
        }
        await waitUntil { core.loadStateCalled }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(core.resumeCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path))
    }

    @MainActor
    private func makeHost(paths: SavePaths, system: SystemID = .gba) throws -> PlayLoadHarness {
        let host = PlayLoadHarness(paths: paths, system: system)
        host.refresh()
        return host
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ predicate: @MainActor () -> Bool
    ) async {
        var waited: UInt64 = 0
        while !predicate() && waited < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 20_000_000)
            waited += 20_000_000
        }
        XCTAssertTrue(predicate(), "Timed out after \(timeoutNanoseconds)ns")
    }

    private func makeSandboxPaths() throws -> (SavePaths, () -> Void) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("rp-load-command-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            SavePaths(fileManager: fileManager, documentsURL: root),
            { try? fileManager.removeItem(at: root) }
        )
    }
}

/// Deletes nothing, so Restart from Scratch sees its save cleanup fail.
private final class FailingRemoveFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

private final class LoadRecordingCore: TestEmulatorCore, @unchecked Sendable {
    let systemID: SystemID
    let coreName = "LoadRecordingCore"
    var supportsSaveState = true
    var supportsFastForward = false
    private(set) var stopCalled = false
    private(set) var pauseCalled = false
    private(set) var resumeCalled = false
    private(set) var loadStateCalled = false
    private(set) var loadedURL: URL?
    var loadError: Error?
    var holdNanoseconds: UInt64 = 0

    init(systemID: SystemID = .gba) {
        self.systemID = systemID
    }
    func start() {}
    func pause() { pauseCalled = true }
    func resume() { resumeCalled = true }
    func stop() { stopCalled = true }
    func saveState(to url: URL) async throws {}
    func loadState(from url: URL) async throws {
        loadedURL = url
        loadStateCalled = true
        if holdNanoseconds > 0 {
            try await Task.sleep(nanoseconds: holdNanoseconds)
        }
        if let loadError { throw loadError }
    }
    func setFastForward(_ enabled: Bool) {}
}

@MainActor
private final class PlayLoadHarness {
    let button = PlayLoadMenuButton()
    let coordinator = PlayLoadActionCoordinator()
    let paths: SavePaths
    let system: SystemID
    let gameID = UUID()
    let coreRecorder: LoadRecordingCore
    var core: (any EmulatorCore)?
    var saveBusy = false
    var entries: [SaveStateStore.Entry] = []
    var statusLine = ""
    var alerts: [String] = []
    var bootCount = 0
    var bootStarted = false
    var delayBoot = false
    var imported = false
    var coordinatorCancelCount = 0

    init(paths: SavePaths, system: SystemID) {
        self.paths = paths
        self.system = system
        coreRecorder = LoadRecordingCore(systemID: system)
        core = coreRecorder
        button.onCommand = { [weak self] command in
            self?.submit(command)
        }
        button.onImportSave = { [weak self] in
            self?.imported = true
        }
    }

    func refresh() {
        entries = SaveStateStore.resolvedEntries(system: system, gameID: gameID, paths: paths)
        button.setEntries(entries)
    }

    func submit(_ command: PlayLoadCommand) {
        coordinator.submit(command) { [weak self] command, stillCurrent in
            guard let self else { return }
            await PlayLoadDriver.run(
                command,
                context: PlayLoadDriver.Context(
                    core: self.core,
                    saveBusy: self.saveBusy,
                    entries: self.entries,
                    wasPaused: false,
                    pausedForBackground: false,
                    system: self.system,
                    gameID: self.gameID,
                    paths: self.paths
                ),
                apply: { self.apply($0) },
                bootFresh: { await self.bootFresh() },
                shouldAbandon: { !stillCurrent() }
            )
        }
    }

    func apply(_ effect: PlayLoadDriver.Effect) {
        switch effect {
        case .status(let line):
            statusLine = line
        case .alert(let message):
            alerts.append(message)
        case .refreshEntries:
            refresh()
        case .setBusy(let busy):
            saveBusy = busy
        }
    }

    func bootFresh() async {
        bootStarted = true
        if delayBoot {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
        }
        if Task.isCancelled {
            return
        }
        bootCount += 1
        core = nil
    }
}

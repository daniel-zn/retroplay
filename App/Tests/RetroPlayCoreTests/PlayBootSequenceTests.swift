// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// Regression tests for Play boot ordering: auto-resume must finish before `start()`.
final class PlayBootSequenceTests: XCTestCase {
    func testPlaybackResumePolicyRequiresExplicitResumeAfterBackgroundPause() {
        XCTAssertFalse(
            PlaybackResumePolicy.shouldResumeAfterOperation(
                userPaused: false,
                pausedForBackground: true
            )
        )
    }

    func testAutoResumeLeavesCorePausedWhenResumeAfterLoadIsFalse() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rp-boot-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let paths = SavePaths(fileManager: fm, documentsURL: root)

        let gameID = UUID()
        let quickURL = try SaveStateStore.quickSaveURL(system: .gba, gameID: gameID, paths: paths)
        try Data("state".utf8).write(to: quickURL)

        let core = BootRecordingCore()
        let status = await AutoResumeLoader.apply(
            core: core,
            system: .gba,
            gameID: gameID,
            paths: paths,
            resumeAfterLoad: false
        )

        XCTAssertEqual(status, .loaded)
        XCTAssertTrue(core.loadStateCalled)
        XCTAssertFalse(core.resumeCalled, "Boot must apply pause/resume after start(), not inside auto-resume")
    }
}

private final class BootRecordingCore: TestEmulatorCore, @unchecked Sendable {
    let systemID: SystemID = .gba
    let coreName = "BootRecordingCore"
    let supportsSaveState = true
    let supportsFastForward = false
    private(set) var loadStateCalled = false
    private(set) var resumeCalled = false
    func start() {}
    func pause() {}
    func resume() { resumeCalled = true }
    func stop() {}
    func saveState(to url: URL) async throws {}
    func loadState(from url: URL) async throws { loadStateCalled = true }
    func setFastForward(_ enabled: Bool) {}
}

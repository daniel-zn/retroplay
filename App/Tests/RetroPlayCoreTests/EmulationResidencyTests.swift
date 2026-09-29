// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// PPSSPP and mupen64plus keep process-global state, so only one game may be loaded
/// on the emulation thread at a time, whatever order the UI's load / stop calls land in.
final class EmulationResidencyTests: XCTestCase {
    private var root: URL!
    private var saves: SavePaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rp-residency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        saves = SavePaths(documentsURL: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSecondLoadTearsDownFirstGameBeforeLoading() async throws {
        let log = DriverEventLog()
        NativeDriverRegistry.register(.gba) { FakeNativeDriver(log: log) }
        let rom = root.appendingPathComponent("game.gba")

        // Quit during "Starting…": the first core's stop() has not been queued yet.
        let first = NativeEmulatorCore(systemID: .gba)
        try await first.loadROM(at: rom, saves: saves)
        first.start()
        let second = NativeEmulatorCore(systemID: .gba)
        try await second.loadROM(at: rom, saves: saves)

        XCTAssertEqual(log.events, ["load 1", "teardown 1", "load 2"])
        await first.stopAndWait()
        await second.stopAndWait()
    }

    func testLateStopOfEvictedCoreLeavesNewGameAlone() async throws {
        let log = DriverEventLog()
        NativeDriverRegistry.register(.gba) { FakeNativeDriver(log: log) }
        let rom = root.appendingPathComponent("game.gba")

        let first = NativeEmulatorCore(systemID: .gba)
        try await first.loadROM(at: rom, saves: saves)
        let second = NativeEmulatorCore(systemID: .gba)
        try await second.loadROM(at: rom, saves: saves)
        second.start()

        await first.stopAndWait()
        XCTAssertEqual(log.events, ["load 1", "teardown 1", "load 2"])
        do {
            try await first.saveState(to: root.appendingPathComponent("evicted.state"))
            XCTFail("An evicted core must not reach the new game's driver")
        } catch {
            XCTAssertEqual(error.localizedDescription, EmulatorCoreError.notRunning.localizedDescription)
        }

        await second.stopAndWait()
        XCTAssertEqual(log.events, ["load 1", "teardown 1", "load 2", "teardown 2"])
    }
}

/// Load / teardown order across drivers, recorded from the emulation thread.
private final class DriverEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    private var nextID = 0

    var events: [String] {
        lock.withLock { _events }
    }

    func makeID() -> Int {
        lock.withLock {
            nextID += 1
            return nextID
        }
    }

    func record(_ event: String) {
        lock.withLock { _events.append(event) }
    }
}

private final class FakeNativeDriver: NativeEmulatorDriver {
    private let log: DriverEventLog
    private let id: Int

    init(log: DriverEventLog) {
        self.log = log
        id = log.makeID()
    }

    func load(romURL: URL, saves: SavePaths) throws { log.record("load \(id)") }
    var frameRate: Double { 60 }
    var audioSampleRate: Double { 0 }
    func setInput(_ input: EmulatorInputState) {}
    func runFrame() {}
    func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int { 0 }
    func copyVideo(into buffer: VideoFrameBuffer) -> Bool { false }
    var supportsSaveStates: Bool { true }
    func saveState(to url: URL) throws { try Data("state".utf8).write(to: url) }
    func loadState(from url: URL) throws {}
    func tearDown() { log.record("teardown \(id)") }
}

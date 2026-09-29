// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@testable import RetroPlayCore

/// Mocks adopt this instead of `EmulatorCore` and override only what a test records.
protocol TestEmulatorCore: EmulatorCore {}

extension TestEmulatorCore {
    var video: VideoFrameStore { VideoFrameStore() }
    var supportsReset: Bool { false }
    func loadROM(at url: URL, saves: SavePaths) async throws {}
    func reset() {}
    func setInput(_ input: EmulatorInputState) {}
    func setAudio(enabled: Bool, respectSilentSwitch: Bool) {}
    func flushSaveData() {}
    func stopAndWait() async { stop() }
    func hadRuntimeError() async -> Bool { false }
}

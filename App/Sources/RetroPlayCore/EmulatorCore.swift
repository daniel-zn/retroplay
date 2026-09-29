// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the Play screen drives. One implementation (`NativeEmulatorCore`) serves every
/// system; the per-system differences live in the registered `NativeEmulatorDriver`.
public protocol EmulatorCore: AnyObject, Sendable {
    var systemID: SystemID { get }
    var coreName: String { get }

    /// Where finished frames appear. Poll it from a display link.
    var video: VideoFrameStore { get }

    /// Load and boot. Battery saves use the `SavePaths` layout.
    func loadROM(at url: URL, saves: SavePaths) async throws
    func start()
    func pause()
    func resume()
    /// Flushes battery saves and tears down asynchronously on the emulation thread.
    func stop()
    /// `stop()`, returning once teardown (and its final battery-save flush) has finished.
    func stopAndWait() async
    func reset()

    /// Latest held input. Cheap and thread-safe; call on every change.
    func setInput(_ input: EmulatorInputState)

    var supportsSaveState: Bool { get }
    var supportsReset: Bool { get }
    var supportsFastForward: Bool { get }
    func setFastForward(_ enabled: Bool)
    func setAudio(enabled: Bool, respectSilentSwitch: Bool)

    func saveState(to url: URL) async throws
    func loadState(from url: URL) async throws
    /// Write battery saves now (app going to background).
    func flushSaveData()
    /// True once the core stopped on an unrecoverable error (e.g. PPSSPP CORE_RUNTIME_ERROR).
    func hadRuntimeError() async -> Bool
}

public enum EmulatorCoreError: Error, Sendable, LocalizedError {
    case notImplemented(String)
    case unsupportedSystem(SystemID)
    case romLoadFailed(String)
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message): return message
        case .unsupportedSystem(let system): return "Unsupported system: \(system.displayName)"
        case .romLoadFailed(let message): return message
        case .notRunning: return "The game is not running."
        }
    }
}

/// Registry of default core names per system.
public enum SystemRegistry {
    public static func defaultCoreName(for system: SystemID) -> String {
        system.defaultCoreName
    }

    public static func system(forFileExtension ext: String) -> SystemID? {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return SystemID.allCases.first { $0.fileExtensions.contains(normalized) }
    }
}

public enum CoreFactory {
    public static func makeCore(for system: SystemID) -> any EmulatorCore {
        NativeEmulatorCore(systemID: system)
    }
}

/// `EmulatorCore` backed by a registered native driver, run on `EmulationThread`.
///
/// Every call from the UI becomes a work item on the emulation thread, so the
/// driver never sees two threads at once (previously input and pause/stop were
/// applied from the main thread while a frame was running).
public final class NativeEmulatorCore: EmulatorCore, @unchecked Sendable {
    public let systemID: SystemID
    public var coreName: String { systemID.defaultCoreName }
    public let video = VideoFrameStore()

    private let thread = EmulationThread.shared
    private let input = InputMailbox()

    /// Emulation-thread only.
    private var loadedSession: EmulationSession?

    /// Emulation-thread only. Nil once another core's load evicted this one's game, so
    /// a late pause / save / stop can never touch a torn-down driver.
    private var session: EmulationSession? {
        guard let loadedSession, thread.isResident(loadedSession) else { return nil }
        return loadedSession
    }

    /// Capabilities, published after a successful load (read from any thread).
    private let capabilityLock = NSLock()
    private var _supportsSaveState = false
    private var _supportsReset = false

    public init(systemID: SystemID) {
        self.systemID = systemID
    }

    public var supportsSaveState: Bool {
        capabilityLock.lock()
        defer { capabilityLock.unlock() }
        return _supportsSaveState
    }

    public var supportsReset: Bool {
        capabilityLock.lock()
        defer { capabilityLock.unlock() }
        return _supportsReset
    }

    public var supportsFastForward: Bool { true }

    public func loadROM(at url: URL, saves: SavePaths) async throws {
        let ext = url.pathExtension.lowercased()
        guard systemID.fileExtensions.contains(ext) else {
            throw EmulatorCoreError.romLoadFailed(
                "\(url.lastPathComponent) is not a \(systemID.displayName) game file (.\(ext))."
            )
        }
        guard let factory = NativeDriverRegistry.factory(for: systemID) else {
            throw EmulatorCoreError.notImplemented(
                "\(coreName) is not built into this copy of RetroPlay. See App/Vendor/XCODE.md to link it."
            )
        }
        try? saves.ensureDirectories()

        let caps: Capabilities = try await thread.perform { [self] in
            // One game at a time: whatever is still loaded (this core's previous game, or
            // another core whose stop() has not run yet) finishes tearing down first.
            thread.evictResident()
            loadedSession = nil
            let driver = factory()
            do {
                try driver.load(romURL: url, saves: saves)
            } catch {
                driver.tearDown()
                throw error
            }
            let session = EmulationSession(driver: driver, video: video, input: input)
            thread.makeResident(session)
            loadedSession = session
            return Capabilities(saveStates: driver.supportsSaveStates, reset: driver.supportsReset)
        }
        capabilityLock.withLock {
            _supportsSaveState = caps.saveStates
            _supportsReset = caps.reset
        }
    }

    public func start() {
        thread.enqueue { [self] in
            guard let session else { return }
            thread.activate(session)
            session.start()
        }
    }

    public func pause() {
        thread.enqueue { [self] in session?.setPaused(true) }
    }

    public func resume() {
        thread.enqueue { [self] in session?.setPaused(false) }
    }

    public func stop() {
        thread.enqueue { [self] in
            guard let loadedSession else { return }
            // No-op if a newer load already evicted (and tore down) this session.
            thread.release(loadedSession)
            self.loadedSession = nil
        }
    }

    public func stopAndWait() async {
        stop()
        // The emulation thread runs work in FIFO order, so this returns after the teardown.
        _ = try? await thread.perform {}
    }

    public func reset() {
        thread.enqueue { [self] in
            guard let session, session.driver.supportsReset else { return }
            session.driver.reset()
            session.resetClock()
        }
    }

    public func setInput(_ input: EmulatorInputState) {
        self.input.store(input)
    }

    public func setFastForward(_ enabled: Bool) {
        thread.enqueue { [self] in
            guard let session else { return }
            session.fastForward = enabled
            session.applyAudioState()
        }
    }

    public func setAudio(enabled: Bool, respectSilentSwitch: Bool) {
        thread.enqueue { [self] in
            guard let session else { return }
            session.audioEnabled = enabled
            session.respectSilentSwitch = respectSilentSwitch
            session.applyAudioState()
        }
    }

    public func saveState(to url: URL) async throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await thread.perform { [self] in
            guard let session else { throw EmulatorCoreError.notRunning }
            // Write to a temp file first so a failed save never destroys the previous one.
            let temp = url.appendingPathExtension("tmp")
            try? FileManager.default.removeItem(at: temp)
            try session.driver.saveState(to: temp)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: url)
            }
        }
    }

    public func loadState(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EmulatorCoreError.romLoadFailed("No save state yet.")
        }
        try await thread.perform { [self] in
            guard let session else { throw EmulatorCoreError.notRunning }
            try session.driver.loadState(from: url)
            session.resetClock()
        }
    }

    public func flushSaveData() {
        thread.enqueue { [self] in session?.driver.flushSaveData() }
    }

    public func hadRuntimeError() async -> Bool {
        (try? await thread.perform { [self] in session?.driver.hadRuntimeError ?? false }) ?? false
    }

    private struct Capabilities: Sendable {
        let saveStates: Bool
        let reset: Bool
    }
}

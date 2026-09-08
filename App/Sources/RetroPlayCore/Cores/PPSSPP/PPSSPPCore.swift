import Foundation

/// M3 PSP host (PPSSPP IR). Native driver registers when XCFramework is linked.
public final class PPSSPPCore: EmulatorCore, CoreRunLoopDriving, @unchecked Sendable {
    public let systemID: SystemID = .psp
    public var coreName: String { "PPSSPP" }

    public private(set) var romURL: URL?
    public private(set) var isRunning = false
    public private(set) var isPaused = false

    private weak var frameSink: EmulatorFrameSink?
    private var native: PPSSPPNativeDriving?
    private let runLoop = CoreRunLoop(label: "RetroPlay.PPSSPPCore")
    private var fastForward = false
    public var supportsSaveState: Bool { true }
    public var supportsFastForward: Bool { true }

    public init() {}

    public func attachFrameSink(_ sink: EmulatorFrameSink?) {
        frameSink = sink
    }

    public func setGBAInput(_ input: GBAInput) {
        _ = input
    }

    public func setPSPInput(_ input: PSPInput) {
        native?.setKeys(input.rawValue)
    }

    public func setFastForward(_ enabled: Bool) {
        runLoop.sync {
            fastForward = enabled
            runLoop.framesPerSecond = enabled ? 90 : 60
        }
    }

    public func loadROM(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard SystemID.psp.fileExtensions.contains(ext) else {
            throw EmulatorCoreError.romLoadFailed("Expected a PSP game (.iso/.cso/.pbp/…), got .\(ext)")
        }
        romURL = url

        guard let factory = PPSSPPNativeRegistry.makeDriver else {
            throw EmulatorCoreError.notImplemented(
                """
                PPSSPP native driver not registered yet. App Store path uses IR interpreter only \
                (\(PPSSPPDefaults.appStoreIniSnippet.trimmingCharacters(in: .whitespacesAndNewlines))). \
                See App/Vendor/PPSSPP.md — build/link an XCFramework on Mac, then register the driver.
                """
            )
        }

        let driver = factory()
        do {
            try driver.loadGame(at: url)
        } catch {
            driver.tearDown()
            throw error
        }
        native?.tearDown()
        native = driver
    }

    public func start() {
        guard native != nil, romURL != nil else { return }
        isRunning = true
        isPaused = false
        native?.resumeAudioVideo()
        runLoop.driver = self
        runLoop.start()
    }

    public func pause() {
        runLoop.sync {
            isPaused = true
            native?.pauseAudioVideo()
        }
    }

    public func resume() {
        runLoop.sync {
            isPaused = false
            native?.resumeAudioVideo()
        }
    }

    public func stop() {
        runLoop.stop()
        runLoop.driver = nil
        isRunning = false
        isPaused = false
        native?.tearDown()
        native = nil
        romURL = nil
    }

    public func saveState(to url: URL) async throws {
        guard native != nil else {
            throw EmulatorCoreError.notImplemented("PPSSPP saveState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("PPSSPP saveState — no native driver")
            }
            try native.saveState(to: url)
        }
    }

    public func loadState(from url: URL) async throws {
        guard native != nil else {
            throw EmulatorCoreError.notImplemented("PPSSPP loadState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("PPSSPP loadState — no native driver")
            }
            try native.loadState(from: url)
        }
    }

    public func runLoopDidTick(_ loop: CoreRunLoop) {
        guard isRunning, !isPaused, let native else { return }
        let steps = fastForward ? 4 : 1
        for _ in 0..<steps {
            native.runFrame()
        }
        if let frame = native.copyRGBAFrame() {
            frameSink?.coreDidProduceVideoFrame(frame)
        }
    }
}

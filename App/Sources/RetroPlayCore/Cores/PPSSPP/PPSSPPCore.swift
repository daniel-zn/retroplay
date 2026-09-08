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
        isPaused = true
        native?.pauseAudioVideo()
    }

    public func resume() {
        isPaused = false
        native?.resumeAudioVideo()
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
        throw EmulatorCoreError.notImplemented("PPSSPP saveState — pending native bridge")
    }

    public func loadState(from url: URL) async throws {
        throw EmulatorCoreError.notImplemented("PPSSPP loadState — pending native bridge")
    }

    public func runLoopDidTick(_ loop: CoreRunLoop) {
        guard isRunning, !isPaused, let native else { return }
        native.runFrame()
        if let frame = native.copyRGBAFrame() {
            frameSink?.coreDidProduceVideoFrame(frame)
        }
    }
}

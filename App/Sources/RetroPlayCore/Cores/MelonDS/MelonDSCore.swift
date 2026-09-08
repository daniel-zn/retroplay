import Foundation

/// M2 NDS host (melonDS interpreter — no JIT).
/// Native driver registers when XCFramework is linked — save/FF stay off until then.
public final class MelonDSCore: EmulatorCore, CoreRunLoopDriving, @unchecked Sendable {
    public let systemID: SystemID = .nds
    public var coreName: String { "melonDS" }

    public private(set) var romURL: URL?
    public private(set) var isRunning = false
    public private(set) var isPaused = false

    private weak var frameSink: EmulatorFrameSink?
    private var currentInput: NDSInput = []
    private var touch = NDSTouch.idle
    private var native: MelonDSNativeDriving?
    private let runLoop = CoreRunLoop(label: "RetroPlay.MelonDSCore")
    private var fastForward = false

    /// False until a real native driver is registered and proven.
    public var supportsSaveState: Bool { false }
    public var supportsFastForward: Bool { false }

    public init() {}

    public func attachFrameSink(_ sink: EmulatorFrameSink?) {
        frameSink = sink
    }

    public func setGBAInput(_ input: GBAInput) {
        _ = input
    }

    public func setPSPInput(_ input: PSPInput) {
        _ = input
    }

    public func setN64Input(_ input: N64Input, stick: N64AnalogStick) {
        _ = input
        _ = stick
    }

    public func setNDSInput(_ input: NDSInput, touch: NDSTouch) {
        currentInput = input
        self.touch = touch
        native?.setKeys(
            input.rawValue,
            touchX: touch.x,
            touchY: touch.y,
            touchPressed: touch.pressed
        )
    }

    public func setFastForward(_ enabled: Bool) {
        runLoop.sync {
            fastForward = enabled
            runLoop.framesPerSecond = enabled ? 90 : 60
        }
    }

    public func loadROM(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard SystemID.nds.fileExtensions.contains(ext) else {
            throw EmulatorCoreError.romLoadFailed("Expected an NDS ROM (.nds/.dsi/…), got .\(ext)")
        }
        romURL = url

        guard let factory = MelonDSNativeRegistry.makeDriver else {
            throw EmulatorCoreError.notImplemented(
                """
                melonDS native driver not registered. On Mac: build melonDS interpreter (no JIT), \
                link App/Vendor/Output/melonDS.xcframework, define RETROPLAY_HAS_MELONDS, and assign MelonDSNativeRegistry.makeDriver \
                (see App/Vendor/melonDS.md and App/Vendor/XCODE.md).
                """
            )
        }

        let driver = factory()
        do {
            try driver.loadROM(at: url)
        } catch {
            driver.tearDown()
            throw error
        }
        native?.tearDown()
        native = driver
        driver.setKeys(
            currentInput.rawValue,
            touchX: touch.x,
            touchY: touch.y,
            touchPressed: touch.pressed
        )
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
            throw EmulatorCoreError.notImplemented("melonDS saveState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("melonDS saveState — no native driver")
            }
            try native.saveState(to: url)
        }
    }

    public func loadState(from url: URL) async throws {
        guard native != nil else {
            throw EmulatorCoreError.notImplemented("melonDS loadState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("melonDS loadState — no native driver")
            }
            try native.loadState(from: url)
        }
    }

    public func runLoopDidTick(_ loop: CoreRunLoop) {
        guard isRunning, !isPaused, let native else { return }
        native.setKeys(
            currentInput.rawValue,
            touchX: touch.x,
            touchY: touch.y,
            touchPressed: touch.pressed
        )
        let steps = fastForward ? 4 : 1
        for _ in 0..<steps {
            native.runFrame()
        }
        if let frame = native.copyRGBAFrame() {
            frameSink?.coreDidProduceVideoFrame(frame)
        }
    }
}

import Foundation

/// M2 N64 host (mupen64plus-next: cached_interpreter + GLideN64/GLES).
/// Native driver registers when XCFramework is linked — save/FF stay off until then.
public final class N64Core: EmulatorCore, CoreRunLoopDriving, @unchecked Sendable {
    public let systemID: SystemID = .n64
    public var coreName: String { "mupen64plus-next" }

    public private(set) var romURL: URL?
    public private(set) var isRunning = false
    public private(set) var isPaused = false

    private weak var frameSink: EmulatorFrameSink?
    private var currentInput: N64Input = []
    private var stick = N64AnalogStick.zero
    private var native: N64NativeDriving?
    private let runLoop = CoreRunLoop(label: "RetroPlay.N64Core")
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
        currentInput = input
        self.stick = stick
        native?.setKeys(input.rawValue, stickX: stick.x, stickY: stick.y)
    }

    public func setNDSInput(_ input: NDSInput, touch: NDSTouch) {
        _ = input
        _ = touch
    }

    public func setFastForward(_ enabled: Bool) {
        runLoop.sync {
            fastForward = enabled
            runLoop.framesPerSecond = enabled ? 90 : 60
        }
    }

    public func loadROM(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard SystemID.n64.fileExtensions.contains(ext) else {
            throw EmulatorCoreError.romLoadFailed("Expected an N64 ROM (.n64/.z64/.v64/…), got .\(ext)")
        }
        romURL = url

        guard let factory = N64NativeRegistry.makeDriver else {
            throw EmulatorCoreError.notImplemented(
                """
                N64 native driver not registered. On Mac: build mupen64plus-next + GLideN64 (cached_interpreter, no paraLLEl-RDP), \
                link App/Vendor/Output/mupen64plus.xcframework, define RETROPLAY_HAS_N64, and assign N64NativeRegistry.makeDriver \
                (see App/Vendor/mupen64plus.md and App/Vendor/XCODE.md).
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
        driver.setKeys(currentInput.rawValue, stickX: stick.x, stickY: stick.y)
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
            throw EmulatorCoreError.notImplemented("N64 saveState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("N64 saveState — no native driver")
            }
            try native.saveState(to: url)
        }
    }

    public func loadState(from url: URL) async throws {
        guard native != nil else {
            throw EmulatorCoreError.notImplemented("N64 loadState — no native driver")
        }
        try runLoop.syncThrows {
            guard let native else {
                throw EmulatorCoreError.notImplemented("N64 loadState — no native driver")
            }
            try native.loadState(from: url)
        }
    }

    public func runLoopDidTick(_ loop: CoreRunLoop) {
        guard isRunning, !isPaused, let native else { return }
        native.setKeys(currentInput.rawValue, stickX: stick.x, stickY: stick.y)
        let steps = fastForward ? 4 : 1
        for _ in 0..<steps {
            native.runFrame()
        }
        if let frame = native.copyRGBAFrame() {
            frameSink?.coreDidProduceVideoFrame(frame)
        }
    }
}

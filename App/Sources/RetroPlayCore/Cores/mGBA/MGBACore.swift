import Foundation

/// M1 GBA core host.
///
/// Native C calls live in the app target (`MGBANativeDriver.swift`) behind the bridging header.
/// Register a driver with `MGBANativeRegistry.makeDriver` after linking `mGBA.xcframework`.
public final class MGBACore: EmulatorCore, CoreRunLoopDriving, @unchecked Sendable {
    public let systemID: SystemID = .gba
    public var coreName: String { "mGBA" }

    public private(set) var romURL: URL?
    public private(set) var isRunning = false
    public private(set) var isPaused = false

    private weak var frameSink: EmulatorFrameSink?
    private var currentInput: GBAInput = []
    private var native: MGBANativeDriving?
    private let runLoop = CoreRunLoop(label: "RetroPlay.MGBACore")

    public init() {}

    public func attachFrameSink(_ sink: EmulatorFrameSink?) {
        frameSink = sink
    }

    public func setGBAInput(_ input: GBAInput) {
        currentInput = input
        native?.setKeys(UInt32(input.rawValue))
    }

    public func loadROM(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        guard ["gba", "agb", "mb"].contains(ext) else {
            throw EmulatorCoreError.romLoadFailed("Expected a GBA ROM, got .\(ext)")
        }
        romURL = url

        guard let factory = MGBANativeRegistry.makeDriver else {
            throw EmulatorCoreError.notImplemented(
                "mGBA native driver not registered. On Mac: link App/Vendor/Output/mGBA.xcframework, set bridging header, define RETROPLAY_HAS_MGBA, and assign MGBANativeRegistry.makeDriver (see App/Vendor/XCODE.md)."
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
        driver.setKeys(UInt32(currentInput.rawValue))
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
        guard let native else {
            throw EmulatorCoreError.notImplemented("mGBA saveState — no native driver")
        }
        try native.saveState(to: url)
    }

    public func loadState(from url: URL) async throws {
        guard let native else {
            throw EmulatorCoreError.notImplemented("mGBA loadState — no native driver")
        }
        try native.loadState(from: url)
    }

    public func runLoopDidTick(_ loop: CoreRunLoop) {
        guard isRunning, !isPaused, let native else { return }
        native.setKeys(UInt32(currentInput.rawValue))
        native.runFrame()
        if let frame = native.copyRGBAFrame() {
            frameSink?.coreDidProduceVideoFrame(frame)
        }
    }
}

public enum CoreFactory {
    public static func makeCore(for system: SystemID) -> any EmulatorCore {
        switch system {
        case .gba:
            return MGBACore()
        case .n64, .nds, .psp:
            return StubEmulatorCore(systemID: system)
        }
    }
}

import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_MGBA
import Darwin

/// Lives in the app target so the Objective-C bridging header can see mGBA C APIs.
public final class MGBANativeDriver: MGBANativeDriving {
    private var core: UnsafeMutablePointer<mCore>?
    private var videoBuffer: UnsafeMutablePointer<mColor>?
    private var width: Int = 0
    private var height: Int = 0
    private var stride: Int = 0
    private var configInitialized = false

    public init() {}

    public func loadROM(at url: URL) throws {
        tearDown()
        let path = url.path
        guard let found = mCoreFind(path) else {
            throw EmulatorCoreError.romLoadFailed("mCoreFind failed for \(url.lastPathComponent)")
        }
        guard found.pointee.`init`(found) else {
            found.pointee.deinit(found)
            throw EmulatorCoreError.romLoadFailed("mCore init failed")
        }

        // Match mGBA SDL: init → InitConfig → LoadConfig → LoadFile → video → reset.
        mCoreInitConfig(found, "retroplay")
        configInitialized = true
        core = found
        mCoreLoadConfig(found)

        guard mCoreLoadFile(found, path) else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("mCoreLoadFile failed")
        }

        var w: UInt32 = 0
        var h: UInt32 = 0
        found.pointee.baseVideoSize(found, &w, &h)
        width = Int(w)
        height = Int(h)
        stride = width
        guard width > 0, height > 0 else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("Invalid video size \(w)x\(h)")
        }

        let count = width * height
        let buffer = UnsafeMutablePointer<mColor>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        found.pointee.setVideoBuffer(found, buffer, stride)
        videoBuffer = buffer

        found.pointee.reset(found)
        _ = mCoreAutoloadSave(found)
    }

    public func setKeys(_ bitmask: UInt32) {
        core?.pointee.setKeys(core, bitmask)
    }

    public func reset() {
        core?.pointee.reset(core)
    }

    public func runFrame() {
        core?.pointee.runFrame(core)
    }

    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}

    public func copyRGBAFrame() -> EmulatorVideoFrame? {
        guard let videoBuffer, width > 0, height > 0 else { return nil }
        let bpp = MemoryLayout<mColor>.size
        let byteCount = width * height * bpp
        let data = Data(bytes: videoBuffer, count: byteCount)
        return EmulatorVideoFrame(
            width: width,
            height: height,
            bytes: data,
            bytesPerRow: width * bpp
        )
    }

    public func saveState(to url: URL) throws {
        guard let core else { throw EmulatorCoreError.notImplemented("no core") }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // SAVESTATE_ALL == 31 (screenshot|savedata|cheats|rtc|metadata)
        let flags: Int32 = 31
        let path = url.path
        guard let vf = VFileOpen(path, O_CREAT | O_TRUNC | O_RDWR) else {
            throw EmulatorCoreError.romLoadFailed("VFileOpen failed for save state")
        }
        defer { _ = vf.pointee.close(vf) }
        if !mCoreSaveStateNamed(core, vf, flags) {
            throw EmulatorCoreError.romLoadFailed("mCoreSaveStateNamed failed")
        }
    }

    public func loadState(from url: URL) throws {
        guard let core else { throw EmulatorCoreError.notImplemented("no core") }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EmulatorCoreError.romLoadFailed("No save state at \(url.lastPathComponent)")
        }
        let flags: Int32 = 31
        guard let vf = VFileOpen(url.path, O_RDONLY) else {
            throw EmulatorCoreError.romLoadFailed("VFileOpen failed for load state")
        }
        defer { _ = vf.pointee.close(vf) }
        if !mCoreLoadStateNamed(core, vf, flags) {
            throw EmulatorCoreError.romLoadFailed("mCoreLoadStateNamed failed")
        }
    }

    public func tearDown() {
        if let core {
            if configInitialized {
                mCoreConfigDeinit(&core.pointee.config)
                configInitialized = false
            }
            core.pointee.deinit(core)
        }
        core = nil
        if let videoBuffer {
            videoBuffer.deallocate()
        }
        videoBuffer = nil
        width = 0
        height = 0
        stride = 0
    }

    deinit { tearDown() }
}

#else

public final class MGBANativeDriver: MGBANativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_MGBA and link mGBA.xcframework."
        )
    }
    public func setKeys(_ bitmask: UInt32) {}
    public func reset() {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MGBA")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MGBA")
    }
    public func tearDown() {}
}

#endif

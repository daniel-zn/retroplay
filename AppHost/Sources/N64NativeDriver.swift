import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_N64

public final class N64NativeDriver: N64NativeDriving {
    private var handle: OpaquePointer?
    private var lastFrame = Data()

    public init() {}

    public func loadROM(at url: URL) throws {
        tearDown()
        guard let h = N64Host_Create() else {
            throw EmulatorCoreError.romLoadFailed("N64Host_Create failed")
        }
        handle = h
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return N64Host_LoadROM(h, path)
        }
        guard ok else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("N64Host_LoadROM failed for \(url.lastPathComponent)")
        }
    }

    public func setKeys(_ bitmask: UInt32, stickX: Int8, stickY: Int8) {
        guard let handle else { return }
        N64Host_SetKeys(handle, bitmask, stickX, stickY)
    }

    public func runFrame() {
        guard let handle else { return }
        N64Host_RunFrame(handle)
    }

    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}

    public func copyRGBAFrame() -> EmulatorVideoFrame? {
        guard let handle else { return nil }
        var w: Int32 = 0
        var h: Int32 = 0
        let capacity = 640 * 480 * 4
        var buf = [UInt8](repeating: 0, count: capacity)
        let n = buf.withUnsafeMutableBytes { raw -> Int in
            N64Host_CopyRGBA(handle, raw.baseAddress, capacity, &w, &h)
        }
        guard n > 0, w > 0, h > 0 else { return nil }
        return EmulatorVideoFrame(
            width: Int(w),
            height: Int(h),
            bytes: Data(buf.prefix(n)),
            bytesPerRow: Int(w) * 4
        )
    }

    public func saveState(to url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notImplemented("no N64 host") }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return N64Host_SaveState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("N64Host_SaveState failed") }
    }

    public func loadState(from url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notImplemented("no N64 host") }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return N64Host_LoadState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("N64Host_LoadState failed") }
    }

    public func tearDown() {
        if let handle {
            N64Host_Destroy(handle)
        }
        handle = nil
    }

    deinit { tearDown() }
}

#else

public final class N64NativeDriver: N64NativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_N64 and link App/Vendor/Output/mupen64plus.xcframework. See App/Vendor/mupen64plus.md."
        )
    }
    public func setKeys(_ bitmask: UInt32, stickX: Int8, stickY: Int8) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_N64")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_N64")
    }
    public func tearDown() {}
}

#endif

import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_MELONDS

public final class MelonDSNativeDriver: MelonDSNativeDriving {
    private var handle: OpaquePointer?
    private var frameBytes = Data()

    public init() {}

    public func loadROM(at url: URL) throws {
        tearDown()
        guard let h = MelonDS_Create() else {
            throw EmulatorCoreError.romLoadFailed("MelonDS_Create failed")
        }
        handle = h
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return MelonDS_LoadROM(h, path)
        }
        guard ok else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("MelonDS_LoadROM failed for \(url.lastPathComponent)")
        }
    }

    public func setKeys(_ bitmask: UInt32, touchX: UInt16, touchY: UInt16, touchPressed: Bool) {
        guard let handle else { return }
        MelonDS_SetKeyMask(handle, bitmask)
        MelonDS_Touch(handle, touchX, touchY, touchPressed)
    }

    public func runFrame() {
        guard let handle else { return }
        MelonDS_RunFrame(handle)
    }

    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}

    public func copyRGBAFrame() -> EmulatorVideoFrame? {
        guard let handle else { return nil }
        var w: Int32 = 0
        var h: Int32 = 0
        let capacity = 256 * 384 * 4
        var buf = [UInt8](repeating: 0, count: capacity)
        let n = buf.withUnsafeMutableBytes { raw -> Int in
            MelonDS_CopyRGBA(handle, raw.baseAddress, capacity, &w, &h)
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
        throw EmulatorCoreError.notImplemented("melonDS saveState not wired yet")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("melonDS loadState not wired yet")
    }

    public func tearDown() {
        if let handle {
            MelonDS_Destroy(handle)
        }
        handle = nil
    }

    deinit { tearDown() }
}

#else

public final class MelonDSNativeDriver: MelonDSNativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_MELONDS and link App/Vendor/Output/melonDS.xcframework. See App/Vendor/melonDS.md."
        )
    }
    public func setKeys(_ bitmask: UInt32, touchX: UInt16, touchY: UInt16, touchPressed: Bool) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MELONDS")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_MELONDS")
    }
    public func tearDown() {}
}

#endif

import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_PPSSPP

public final class PPSSPPNativeDriver: PPSSPPNativeDriving {
    private var bridge: OpaquePointer?

    public init() {}

    public func loadGame(at url: URL) throws {
        tearDown()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let save = docs.appendingPathComponent("PPSSPP", isDirectory: true)
        let cache = docs.appendingPathComponent("PPSSPPCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        guard let created = rp_ppsspp_create(save.path, cache.path) else {
            throw EmulatorCoreError.romLoadFailed("rp_ppsspp_create failed")
        }
        bridge = OpaquePointer(created)

        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_load(created, pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            tearDown()
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP load failed" : message)
        }
    }

    public func setKeys(_ bitmask: UInt32) {
        guard let bridge else { return }
        rp_ppsspp_set_buttons(UnsafeMutableRawPointer(bridge), bitmask)
    }

    public func runFrame() {
        guard let bridge else { return }
        rp_ppsspp_run_frame(UnsafeMutableRawPointer(bridge))
    }

    public func pauseAudioVideo() {
        guard let bridge else { return }
        rp_ppsspp_pause(UnsafeMutableRawPointer(bridge))
    }

    public func resumeAudioVideo() {
        guard let bridge else { return }
        rp_ppsspp_resume(UnsafeMutableRawPointer(bridge))
    }

    public func copyRGBAFrame() -> EmulatorVideoFrame? {
        guard let bridge else { return nil }
        var bytes: UnsafeMutablePointer<UInt8>?
        var w: Int32 = 0
        var h: Int32 = 0
        var stride: Int32 = 0
        let ok = rp_ppsspp_copy_rgba(UnsafeMutableRawPointer(bridge), &bytes, &w, &h, &stride)
        guard ok, let bytes, w > 0, h > 0, stride > 0 else { return nil }
        defer { free(bytes) }
        let count = Int(stride) * Int(h)
        let data = Data(bytes: bytes, count: count)
        return EmulatorVideoFrame(width: Int(w), height: Int(h), bytes: data, bytesPerRow: Int(stride))
    }

    public func saveState(to url: URL) throws {
        guard let bridge else { throw EmulatorCoreError.notImplemented("no bridge") }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_save_state(UnsafeMutableRawPointer(bridge), pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP save state failed" : message)
        }
    }

    public func loadState(from url: URL) throws {
        guard let bridge else { throw EmulatorCoreError.notImplemented("no bridge") }
        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_load_state(UnsafeMutableRawPointer(bridge), pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP load state failed" : message)
        }
    }

    public func tearDown() {
        if let bridge {
            rp_ppsspp_destroy(UnsafeMutableRawPointer(bridge))
        }
        bridge = nil
    }

    deinit { tearDown() }
}

#else

public final class PPSSPPNativeDriver: PPSSPPNativeDriving {
    public init() {}
    public func loadGame(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile with RETROPLAY_HAS_PPSSPP and link App/Vendor/Output/PPSSPP.xcframework. See App/Vendor/PPSSPP.md."
        )
    }
    public func setKeys(_ bitmask: UInt32) {}
    public func runFrame() {}
    public func pauseAudioVideo() {}
    public func resumeAudioVideo() {}
    public func copyRGBAFrame() -> EmulatorVideoFrame? { nil }
    public func saveState(to url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_PPSSPP")
    }
    public func loadState(from url: URL) throws {
        throw EmulatorCoreError.notImplemented("needs RETROPLAY_HAS_PPSSPP")
    }
    public func tearDown() {}
}

#endif

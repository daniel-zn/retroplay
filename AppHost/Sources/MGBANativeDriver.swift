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
        // GBA reset reads the config hash table; must init before reset/load.
        mCoreInitConfig(found, "retroplay")
        guard mCoreLoadFile(found, path) else {
            found.pointee.deinit(found)
            throw EmulatorCoreError.romLoadFailed("mCoreLoadFile failed")
        }

        var w: UInt32 = 0
        var h: UInt32 = 0
        found.pointee.baseVideoSize(found, &w, &h)
        width = Int(w)
        height = Int(h)
        stride = width
        guard width > 0, height > 0 else {
            found.pointee.deinit(found)
            throw EmulatorCoreError.romLoadFailed("Invalid video size")
        }

        let count = width * height
        let buffer = UnsafeMutablePointer<mColor>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        found.pointee.setVideoBuffer(found, buffer, stride)
        found.pointee.reset(found)
        _ = mCoreAutoloadSave(found)

        videoBuffer = buffer
        core = found
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
        // Default mColor is uint32 RGBA-like (see mgba-util/image.h without COLOR_16_BIT).
        let byteCount = width * height * MemoryLayout<mColor>.size
        let data = Data(bytes: videoBuffer, count: byteCount)
        return EmulatorVideoFrame(
            width: width,
            height: height,
            bytes: data,
            bytesPerRow: width * MemoryLayout<mColor>.size
        )
    }

    public func saveState(to url: URL) throws {
        // Slot 1 via mGBA helper; path-based named states can be added once VFile helpers are verified on Mac.
        guard let core else { throw EmulatorCoreError.notImplemented("no core") }
        _ = url // reserved for named-state path
        if !mCoreSaveState(core, 1, 0) {
            throw EmulatorCoreError.romLoadFailed("mCoreSaveState(slot 1) failed")
        }
    }

    public func loadState(from url: URL) throws {
        guard let core else { throw EmulatorCoreError.notImplemented("no core") }
        _ = url
        if !mCoreLoadState(core, 1, 0) {
            throw EmulatorCoreError.romLoadFailed("mCoreLoadState(slot 1) failed")
        }
    }

    public func tearDown() {
        if let core {
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

/// Placeholder so the package/app sources compile without the XCFramework.
public final class MGBANativeDriver: MGBANativeDriving {
    public init() {}
    public func loadROM(at url: URL) throws {
        throw EmulatorCoreError.notImplemented(
            "Compile the app with RETROPLAY_HAS_MGBA and link mGBA.xcframework (see App/Vendor/XCODE.md)."
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

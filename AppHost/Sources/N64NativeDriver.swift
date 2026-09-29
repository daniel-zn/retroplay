// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_N64

/// mupen64plus-next via the in-process libretro host. Called only on the emulation
/// thread, which also owns the GLES context (no more hopping to the main thread).
public final class N64NativeDriver: NativeEmulatorDriver {
    private var handle: OpaquePointer?

    public init() {}

    public var frameRate: Double {
        guard let handle else { return SystemID.n64.nominalFrameRate }
        return N64Host_FrameRate(handle)
    }

    public var audioSampleRate: Double {
        guard let handle else { return 0 }
        return N64Host_SampleRate(handle)
    }

    public var supportsSaveStates: Bool { true }
    public var supportsReset: Bool { true }

    public func load(romURL url: URL, saves: SavePaths) throws {
        tearDown()
        guard let h = N64Host_Create() else {
            throw EmulatorCoreError.romLoadFailed("The N64 core could not start")
        }
        handle = h
        let sram = saves.n64SRAMURL(forRelativeROMPath: saves.relativeROMPath(fromAbsoluteROMURL: url))
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return sram.withUnsafeFileSystemRepresentation { sramPath in
                N64Host_LoadROM(h, path, sramPath)
            }
        }
        guard ok else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("The N64 core could not load \(url.lastPathComponent)")
        }
    }

    public func setInput(_ input: EmulatorInputState) {
        guard let handle else { return }
        N64Host_SetKeys(handle, input.buttons, input.analogX, input.analogY)
    }

    public func runFrame() {
        guard let handle else { return }
        N64Host_RunFrame(handle)
    }

    public func reset() {
        guard let handle else { return }
        N64Host_Reset(handle)
    }

    public func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        guard let handle else { return 0 }
        return Int(N64Host_ReadAudio(handle, buffer, Int32(clamping: maxFrames)))
    }

    public func copyVideo(into frame: VideoFrameBuffer) -> Bool {
        guard let handle else { return false }
        var w: Int32 = 0
        var h: Int32 = 0
        guard let src = N64Host_Frame(handle, &w, &h), w > 0, h > 0 else { return false }
        let dst = frame.prepare(width: Int(w), height: Int(h))
        memcpy(dst, src, Int(w) * Int(h) * 4)
        return true
    }

    public func flushSaveData() {
        guard let handle else { return }
        N64Host_FlushSaveData(handle)
    }

    public func saveState(to url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return N64Host_SaveState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("The N64 core could not write the save state") }
    }

    public func loadState(from url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return N64Host_LoadState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("That N64 save state could not be loaded") }
    }

    public func tearDown() {
        if let handle {
            N64Host_Destroy(handle)
        }
        handle = nil
    }

    deinit { tearDown() }
}

#endif

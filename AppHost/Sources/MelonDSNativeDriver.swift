// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_MELONDS

/// melonDS interpreter (no JIT). Called only on the emulation thread.
public final class MelonDSNativeDriver: NativeEmulatorDriver {
    private var handle: OpaquePointer?

    public init() {}

    public var frameRate: Double { SystemID.nds.nominalFrameRate }
    public var audioSampleRate: Double { MelonDS_SampleRate() }
    public var supportsSaveStates: Bool { true }
    public var supportsReset: Bool { true }

    public func load(romURL url: URL, saves: SavePaths) throws {
        tearDown()
        guard let h = MelonDS_Create() else {
            throw EmulatorCoreError.romLoadFailed("melonDS could not start")
        }
        handle = h
        let save = saves.sramURL(forRelativeROMPath: saves.relativeROMPath(fromAbsoluteROMURL: url))
        try? FileManager.default.createDirectory(
            at: save.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return save.withUnsafeFileSystemRepresentation { savePath in
                MelonDS_LoadROM(h, path, savePath)
            }
        }
        guard ok else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("melonDS could not load \(url.lastPathComponent)")
        }
    }

    public func setInput(_ input: EmulatorInputState) {
        guard let handle else { return }
        MelonDS_SetKeyMask(handle, input.buttons & 0xFFF)
        MelonDS_Touch(handle, input.touchX, input.touchY, input.touching)
    }

    public func runFrame() {
        guard let handle else { return }
        MelonDS_RunFrame(handle)
    }

    public func reset() {
        guard let handle else { return }
        MelonDS_Reset(handle)
    }

    public func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        guard let handle else { return 0 }
        return Int(MelonDS_ReadAudio(handle, buffer, Int32(clamping: maxFrames)))
    }

    public func copyVideo(into frame: VideoFrameBuffer) -> Bool {
        guard let handle else { return false }
        var w: Int32 = 0
        var h: Int32 = 0
        let dst = frame.prepare(width: 256, height: 384)
        let n = MelonDS_CopyRGBA(handle, dst, 256 * 384 * 4, &w, &h)
        return n > 0 && w == 256 && h == 384
    }

    public func flushSaveData() {
        guard let handle else { return }
        MelonDS_FlushSave(handle)
    }

    public func saveState(to url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return MelonDS_SaveState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("melonDS could not write the save state") }
    }

    public func loadState(from url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return MelonDS_LoadState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("That DS save state could not be loaded") }
    }

    public func tearDown() {
        if let handle {
            MelonDS_Destroy(handle)
        }
        handle = nil
    }

    deinit { tearDown() }
}

#endif

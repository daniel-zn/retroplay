// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_MGBA
import Darwin

/// Lives in the app target so the Objective-C bridging header can see mGBA C APIs.
/// Called only on the emulation thread.
public final class MGBANativeDriver: NativeEmulatorDriver {
    private var core: UnsafeMutablePointer<mCore>?
    private var videoBuffer: UnsafeMutablePointer<mColor>?
    private var width: Int = 0
    private var height: Int = 0
    private var configInitialized = false

    public init() {}

    public var frameRate: Double { SystemID.gba.nominalFrameRate }

    public var audioSampleRate: Double {
        guard let core else { return 0 }
        return Double(core.pointee.audioSampleRate(core))
    }

    public var supportsSaveStates: Bool { true }
    public var supportsReset: Bool { true }

    public func load(romURL url: URL, saves: SavePaths) throws {
        tearDown()
        let sram = saves.sramURL(forRelativeROMPath: saves.relativeROMPath(fromAbsoluteROMURL: url))
        try? FileManager.default.createDirectory(
            at: sram.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let path = url.path
        guard let found = mCoreFind(path) else {
            throw EmulatorCoreError.romLoadFailed("mGBA could not recognise \(url.lastPathComponent)")
        }
        guard found.pointee.`init`(found) else {
            found.pointee.deinit(found)
            throw EmulatorCoreError.romLoadFailed("mGBA failed to initialise")
        }

        // Match mGBA SDL: init → InitConfig → LoadConfig → LoadFile → video → reset.
        mCoreInitConfig(found, "retroplay")
        // Without a default, opts.volume maps to 0 and the GBA mixes silence.
        // mGBA's own frontends default to 0x100 (GBA_AUDIO_VOLUME_MAX).
        mCoreConfigSetDefaultIntValue(&found.pointee.config, "volume", 0x100)
        configInitialized = true
        core = found
        mCoreLoadConfig(found)

        guard mCoreLoadFile(found, path) else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("mGBA could not load \(url.lastPathComponent)")
        }

        var w: UInt32 = 0
        var h: UInt32 = 0
        found.pointee.baseVideoSize(found, &w, &h)
        width = Int(w)
        height = Int(h)
        guard width > 0, height > 0 else {
            tearDown()
            throw EmulatorCoreError.romLoadFailed("Invalid video size \(w)x\(h)")
        }

        let count = width * height
        let buffer = UnsafeMutablePointer<mColor>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        found.pointee.setVideoBuffer(found, buffer, width)
        videoBuffer = buffer

        // Room for several frames at the highest SOUNDBIAS rate; drained after every frame.
        found.pointee.setAudioBufferSize(found, 8192)

        found.pointee.reset(found)
        // Writable save file under Saves/ (same write-through as mCoreAutoloadSave).
        _ = mCoreLoadSaveFile(found, sram.path, false)
    }

    public func setInput(_ input: EmulatorInputState) {
        guard let core else { return }
        core.pointee.setKeys(core, input.buttons & 0x3FF)
    }

    public func reset() {
        guard let core else { return }
        core.pointee.reset(core)
    }

    public func runFrame() {
        guard let core else { return }
        core.pointee.runFrame(core)
    }

    public func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        guard let core, let audio = core.pointee.getAudioBuffer(core) else { return 0 }
        return Int(mAudioBufferRead(audio, buffer, maxFrames))
    }

    public func copyVideo(into frame: VideoFrameBuffer) -> Bool {
        // 32-bit mColor is R,G,B,X in memory. A COLOR_16_BIT build is not supported.
        guard let videoBuffer, width > 0, height > 0, MemoryLayout<mColor>.size == 4 else { return false }
        let dst = frame.prepare(width: width, height: height)
        memcpy(dst, videoBuffer, width * height * 4)
        return true
    }

    public func saveState(to url: URL) throws {
        guard let core else { throw EmulatorCoreError.notRunning }
        // SAVESTATE_ALL == 31 (screenshot|savedata|cheats|rtc|metadata)
        let flags: Int32 = 31
        guard let vf = VFileOpen(url.path, O_CREAT | O_TRUNC | O_RDWR) else {
            throw EmulatorCoreError.romLoadFailed("Could not create the save state file")
        }
        defer { _ = vf.pointee.close(vf) }
        if !mCoreSaveStateNamed(core, vf, flags) {
            throw EmulatorCoreError.romLoadFailed("mGBA could not write the save state")
        }
    }

    public func loadState(from url: URL) throws {
        guard let core else { throw EmulatorCoreError.notRunning }
        // Restore CPU/RAM only; keep the cartridge save on disk as the source of truth.
        let flags: Int32 = 31 & ~2 // drop SAVESTATE_SAVEDATA
        guard let vf = VFileOpen(url.path, O_RDONLY) else {
            throw EmulatorCoreError.romLoadFailed("Could not open the save state file")
        }
        defer { _ = vf.pointee.close(vf) }
        if !mCoreLoadStateNamed(core, vf, flags) {
            throw EmulatorCoreError.romLoadFailed("That save state could not be loaded")
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
        videoBuffer?.deallocate()
        videoBuffer = nil
        width = 0
        height = 0
    }

    deinit { tearDown() }
}

#endif

// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_PPSSPP

/// PPSSPP (IR interpreter, SoftGPU). Called only on the emulation thread.
public final class PPSSPPNativeDriver: NativeEmulatorDriver {
    private var bridge: UnsafeMutableRawPointer?
    private var lastButtons: UInt32 = .max
    private var lastAnalog: (Float, Float) = (.nan, .nan)

    public init() {}

    public var frameRate: Double { SystemID.psp.nominalFrameRate }
    public var audioSampleRate: Double { 44_100 }
    public var supportsSaveStates: Bool { true }

    public func load(romURL url: URL, saves: SavePaths) throws {
        tearDown()
        // PPSSPP keeps its own memory stick (PSP/SAVEDATA) under Saves/psp-memstick.
        try saves.ensureDirectories()
        let save = saves.pspMemstickDirectory
        let cache = saves.cacheDirectory.appendingPathComponent("psp", isDirectory: true)
        try PPSSPPHostConfig.ensureMemstickDefaults(at: save)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        guard PPSSPPHostConfig.memstickLooksReady(at: save) else {
            throw EmulatorCoreError.romLoadFailed("PSP memstick folders are not ready under Saves/psp-memstick.")
        }

        guard let created = rp_ppsspp_create(save.path, cache.path) else {
            throw EmulatorCoreError.romLoadFailed("PPSSPP could not start")
        }
        bridge = created

        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_load(created, pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            tearDown()
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP could not load this game" : message)
        }
        lastButtons = .max
        lastAnalog = (.nan, .nan)
    }

    public func setInput(_ input: EmulatorInputState) {
        guard let bridge else { return }
        if input.buttons != lastButtons {
            lastButtons = input.buttons
            rp_ppsspp_set_buttons(bridge, input.buttons)
        }
        if input.analogX != lastAnalog.0 || input.analogY != lastAnalog.1 {
            lastAnalog = (input.analogX, input.analogY)
            rp_ppsspp_set_analog(bridge, input.analogX, input.analogY)
        }
    }

    public func runFrame() {
        guard let bridge else { return }
        rp_ppsspp_run_frame(bridge)
    }

    public func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        guard let bridge else { return 0 }
        return Int(rp_ppsspp_read_audio(bridge, buffer, Int32(clamping: maxFrames)))
    }

    public func copyVideo(into frame: VideoFrameBuffer) -> Bool {
        guard let bridge else { return false }
        var bytes: UnsafeMutablePointer<UInt8>?
        var w: Int32 = 0
        var h: Int32 = 0
        var stride: Int32 = 0
        let ok = rp_ppsspp_copy_rgba(bridge, &bytes, &w, &h, &stride)
        guard ok, let bytes else { return false }
        defer { free(bytes) }
        guard w > 0, h > 0, stride >= w * 4 else { return false }
        let width = Int(w)
        let height = Int(h)
        let dst = frame.prepare(width: width, height: height)
        let rowBytes = width * 4
        for y in 0..<height {
            memcpy(dst + y * rowBytes, bytes + y * Int(stride), rowBytes)
        }
        return true
    }

    public func saveState(to url: URL) throws {
        guard let bridge else { throw EmulatorCoreError.notRunning }
        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_save_state(bridge, pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP save state failed" : message)
        }
    }

    public func loadState(from url: URL) throws {
        guard let bridge else { throw EmulatorCoreError.notRunning }
        var err = [CChar](repeating: 0, count: 1024)
        let ok = url.path.withCString { pathPtr in
            rp_ppsspp_load_state(bridge, pathPtr, &err, err.count)
        }
        if !ok {
            let message = String(cString: err)
            throw EmulatorCoreError.romLoadFailed(message.isEmpty ? "PPSSPP load state failed" : message)
        }
        // The restored game has its own idea of held buttons; resend ours next frame.
        lastButtons = .max
        lastAnalog = (.nan, .nan)
    }

    /// The PSP CPU stopped on an unrecoverable error; frames no longer advance.
    public var hadRuntimeError: Bool {
        guard let bridge else { return false }
        return rp_ppsspp_had_runtime_error(bridge)
    }

    public func tearDown() {
        if let bridge {
            rp_ppsspp_destroy(bridge)
        }
        bridge = nil
    }

    deinit { tearDown() }
}

#endif

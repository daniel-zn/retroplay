// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import IOSurface
import RetroPlayCore

#if RETROPLAY_HAS_PPSSPP

/// PPSSPP (IR interpreter; Vulkan on MoltenVK, or the software renderer if the device can't).
/// Called only on the emulation thread, except for GPU frames, which arrive on PPSSPP's
/// present thread and go straight to the frame store.
public final class PPSSPPNativeDriver: NativeEmulatorDriver {
    private var bridge: UnsafeMutableRawPointer?
    private var lastButtons: UInt32 = .max
    private var lastAnalog: (Float, Float) = (.nan, .nan)
    private let frames = PSPFrameSink()
    private var framesSinceScaleCheck = 0
    private var renderScale = 0
    /// How often (in frames) the internal resolution is matched to the screen again. Also
    /// keeps a rotation's in-between sizes from each rebuilding the GPU framebuffers.
    private static let scaleCheckInterval = 30

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
        rp_ppsspp_set_frame_callback(created, { context, surface in
            guard let context, let surface else { return }
            let sink = Unmanaged<PSPFrameSink>.fromOpaque(context).takeUnretainedValue()
            sink.publish(Unmanaged<IOSurface>.fromOpaque(surface).takeUnretainedValue())
        }, Unmanaged.passUnretained(frames).toOpaque())
        renderScale = 0
        updateRenderScale()

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

    public func willSuspend() {
        guard let bridge else { return }
        rp_ppsspp_save_caches(bridge)
    }

    public func attachVideo(_ store: VideoFrameStore) {
        frames.store = store
        updateRenderScale()
    }

    public func runFrame() {
        guard let bridge else { return }
        framesSinceScaleCheck += 1
        if framesSinceScaleCheck >= Self.scaleCheckInterval {
            updateRenderScale()
        }
        rp_ppsspp_run_frame(bridge)
    }

    /// The Resolution option, or for Auto the size the picture is shown at.
    private func updateRenderScale() {
        framesSinceScaleCheck = 0
        guard let bridge else { return }
        let display = frames.store?.largestDisplaySize ?? .zero
        let scale = PSPRenderResolution.current().scale(forDisplayPixels: display)
        if scale != renderScale {
            renderScale = scale
            rp_ppsspp_set_render_scale(bridge, Int32(scale))
        }
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
    public func setFastForward(_ enabled: Bool) {
        guard let bridge else { return }
        rp_ppsspp_set_fast_forward(bridge, enabled)
    }

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

/// Where PPSSPP's present thread hands finished GPU frames.
private final class PSPFrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storage: VideoFrameStore?

    var store: VideoFrameStore? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    func publish(_ surface: IOSurface) {
        store?.publish(surface: surface)
    }
}

#endif

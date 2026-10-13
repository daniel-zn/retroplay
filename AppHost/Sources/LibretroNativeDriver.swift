// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

#if RETROPLAY_HAS_LIBRETRO

/// A libretro core (NES, SNES, Genesis, Atari 7800, PS1) through `LibretroHost`, which
/// loads the core's framework at runtime. Called only on the emulation thread.
public final class LibretroNativeDriver: NativeEmulatorDriver {
    private let system: SystemID
    private var handle: OpaquePointer?

    public init(system: SystemID) {
        self.system = system
    }

    /// Options RetroPlay pins over the core's defaults.
    static func options(for system: SystemID) -> [String: String] {
        switch system {
        case .ps1:
            // iOS apps can't run generated code: interpreter only. A real BIOS in BIOS/ is
            // used when present; otherwise the core's built-in replacement.
            return ["pcsx_rearmed_drc": "disabled", "pcsx_rearmed_bios": "auto"]
        default:
            return [:]
        }
    }

    public var frameRate: Double {
        guard let handle else { return system.nominalFrameRate }
        return LibretroHost_FrameRate(handle)
    }

    public var audioSampleRate: Double {
        guard let handle else { return 0 }
        return LibretroHost_SampleRate(handle)
    }

    public var supportsSaveStates: Bool { true }
    public var supportsReset: Bool { true }

    public func load(romURL url: URL, saves: SavePaths) throws {
        tearDown()
        guard let core = system.libretroCore else {
            throw EmulatorCoreError.romLoadFailed("\(system.displayName) has no core")
        }
        let fileManager = FileManager.default
        let relative = saves.relativeROMPath(fromAbsoluteROMURL: url)
        let sram = saves.sramURL(forRelativeROMPath: relative)
        let coreSaves = saves.savesDirectory.appendingPathComponent(system.rawValue, isDirectory: true)
        for directory in [saves.biosDirectory, coreSaves, sram.deletingLastPathComponent()] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let created = saves.biosDirectory.withUnsafeFileSystemRepresentation { bios in
            coreSaves.withUnsafeFileSystemRepresentation { saveDir in
                LibretroHost_Create(core, bios, saveDir)
            }
        }
        guard let h = created else {
            throw EmulatorCoreError.romLoadFailed("The \(system.displayName) core could not start")
        }
        handle = h
        for (key, value) in Self.options(for: system) {
            LibretroHost_SetOption(h, key, value)
        }
        var reason: UnsafePointer<CChar>?
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return sram.withUnsafeFileSystemRepresentation { sramPath in
                LibretroHost_Load(h, path, sramPath, &reason)
            }
        }
        guard ok else {
            let why = reason.map { String(cString: $0) } ?? "it could not be loaded"
            tearDown()
            throw EmulatorCoreError.romLoadFailed("\(url.lastPathComponent): \(why)")
        }
    }

    public func setInput(_ input: EmulatorInputState) {
        guard let handle else { return }
        LibretroHost_SetInput(handle, input.buttons, input.analogX, input.analogY)
    }

    public func runFrame() {
        guard let handle else { return }
        LibretroHost_RunFrame(handle)
    }

    public func reset() {
        guard let handle else { return }
        LibretroHost_Reset(handle)
    }

    public func readAudio(into buffer: UnsafeMutablePointer<Int16>, maxFrames: Int) -> Int {
        guard let handle else { return 0 }
        return Int(LibretroHost_ReadAudio(handle, buffer, Int32(clamping: maxFrames)))
    }

    public func copyVideo(into frame: VideoFrameBuffer) -> Bool {
        guard let handle else { return false }
        var w: Int32 = 0
        var h: Int32 = 0
        guard let src = LibretroHost_Frame(handle, &w, &h), w > 0, h > 0 else { return false }
        let dst = frame.prepare(width: Int(w), height: Int(h))
        memcpy(dst, src, Int(w) * Int(h) * 4)
        return true
    }

    public func flushSaveData() {
        guard let handle else { return }
        LibretroHost_FlushSaveData(handle)
    }

    public func saveState(to url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return LibretroHost_SaveState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("The \(system.displayName) core could not write the save state") }
    }

    public func loadState(from url: URL) throws {
        guard let handle else { throw EmulatorCoreError.notRunning }
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return LibretroHost_LoadState(handle, path)
        }
        if !ok { throw EmulatorCoreError.romLoadFailed("That \(system.displayName) save state could not be loaded") }
    }

    public func tearDown() {
        if let handle {
            LibretroHost_Destroy(handle)
        }
        handle = nil
    }

    deinit { tearDown() }
}

#endif

/// Call from `@main` app init. Registers every libretro system when the cores are bundled.
public enum LibretroNativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_LIBRETRO
        for system in SystemID.allCases where system.libretroCore != nil {
            NativeDriverRegistry.register(system) { LibretroNativeDriver(system: system) }
        }
        #endif
    }
}

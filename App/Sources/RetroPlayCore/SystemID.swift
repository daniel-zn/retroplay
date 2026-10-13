// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Every system RetroPlay plays. Raw values are stored in library.json and folder names.
public enum SystemID: String, CaseIterable, Codable, Sendable, Identifiable {
    case gba
    case n64
    case nds
    case psp
    case nes
    case snes
    case genesis
    case atari7800
    case ps1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gba: return "Game Boy Advance"
        case .n64: return "Nintendo 64"
        case .nds: return "Nintendo DS"
        case .psp: return "PlayStation Portable"
        case .nes: return "Nintendo Entertainment System"
        case .snes: return "Super Nintendo"
        case .genesis: return "Sega Genesis"
        case .atari7800: return "Atari 7800"
        case .ps1: return "PlayStation"
        }
    }

    /// The bundled emulator core.
    public var defaultCoreName: String {
        switch self {
        case .gba: return "mGBA"
        case .n64: return "mupen64plus-next"
        case .nds: return "melonDS"
        case .psp: return "PPSSPP"
        case .nes: return "Nestopia UE"
        case .snes: return "bsnes"
        case .genesis: return "clownmdemu"
        case .atari7800: return "ProSystem"
        case .ps1: return "PCSX-ReARMed"
        }
    }

    /// Framework name of the libretro core that runs this system, loaded at runtime
    /// (nil for the systems with their own native bridge).
    public var libretroCore: String? {
        switch self {
        case .gba, .n64, .nds, .psp: return nil
        case .nes: return "nestopia"
        case .snes: return "bsnes"
        case .genesis: return "clownmdemu"
        case .atari7800: return "prosystem"
        case .ps1: return "pcsx_rearmed"
        }
    }

    /// ROM / disc extensions that belong to this system. Extensions two systems share
    /// (`iso`, `chd`, `pbp` for PSP and PS1; `bin` for Genesis and PS1) are listed under
    /// each, and `DiscSniffer` picks the system from the file's contents.
    public var fileExtensions: Set<String> {
        switch self {
        // No ".zip": none of the bundled cores unpack archives, and a zip cannot be
        // routed to one system by extension alone.
        case .gba: return ["gba", "agb", "mb"]
        case .n64: return ["n64", "z64", "v64"]
        case .nds: return ["nds", "dsi"]
        case .psp: return ["iso", "cso", "chd", "pbp", "prx", "elf"]
        case .nes: return ["nes", "unf", "unif"]
        case .snes: return ["sfc", "smc"]
        case .genesis: return ["md", "gen", "smd", "bin"]
        case .atari7800: return ["a78"]
        // .exe: homebrew as a bare PS-X EXE (checked by DiscSniffer).
        case .ps1: return ["cue", "chd", "pbp", "bin", "iso", "exe"]
        }
    }

    /// Native video size (NDS is both screens stacked).
    public var nativeScreenSize: (width: Int, height: Int) {
        switch self {
        case .gba: return (240, 160)
        case .n64: return (640, 480)
        case .nds: return (256, 384)
        case .psp: return (480, 272)
        case .nes: return (256, 240)
        case .snes: return (256, 224)
        case .genesis: return (320, 224)
        case .atari7800: return (320, 223)
        case .ps1: return (320, 240)
        }
    }

    /// Display aspect ratio (width / height) of the whole game image.
    public var screenAspect: Double {
        switch self {
        case .gba: return 3.0 / 2.0
        case .n64: return 4.0 / 3.0
        case .nds: return 256.0 / 384.0
        case .psp: return 480.0 / 272.0
        // TV consoles: the picture is 4:3 whatever the core's pixel grid.
        case .nes, .snes, .genesis, .atari7800, .ps1: return 4.0 / 3.0
        }
    }

    /// Hardware refresh rate used for frame pacing until the core reports its own.
    public var nominalFrameRate: Double {
        switch self {
        case .gba: return 16_777_216.0 / 280_896.0 // 59.7275
        case .n64: return 60.0
        case .nds: return 33_513_982.0 / 560_190.0 // 59.8261
        case .psp: return 59.94
        case .nes, .snes: return 60.0988
        case .genesis: return 59.9227
        case .atari7800: return 60.0
        case .ps1: return 59.94
        }
    }
}

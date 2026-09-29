// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Locked P0 systems only. Do not add NES/SNES/GB here without a scope change.
public enum SystemID: String, CaseIterable, Codable, Sendable, Identifiable {
    case gba
    case n64
    case nds
    case psp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gba: return "Game Boy Advance"
        case .n64: return "Nintendo 64"
        case .nds: return "Nintendo DS"
        case .psp: return "PlayStation Portable"
        }
    }

    /// Default bundled core family (name only — no binary vendored yet).
    public var defaultCoreName: String {
        switch self {
        case .gba: return "mGBA"
        case .n64: return "mupen64plus-next"
        case .nds: return "melonDS"
        case .psp: return "PPSSPP"
        }
    }

    /// Common ROM / disc extensions for Files import matching.
    public var fileExtensions: Set<String> {
        switch self {
        // No ".zip": none of the bundled cores unpack archives, and a zip cannot be
        // routed to one system by extension alone.
        case .gba: return ["gba", "agb", "mb"]
        case .n64: return ["n64", "z64", "v64"]
        case .nds: return ["nds", "dsi"]
        case .psp: return ["iso", "cso", "chd", "pbp", "prx", "elf"]
        }
    }

    /// Native video size (NDS is both screens stacked).
    public var nativeScreenSize: (width: Int, height: Int) {
        switch self {
        case .gba: return (240, 160)
        case .n64: return (640, 480)
        case .nds: return (256, 384)
        case .psp: return (480, 272)
        }
    }

    /// Display aspect ratio (width / height) of the whole game image.
    public var screenAspect: Double {
        switch self {
        case .gba: return 3.0 / 2.0
        case .n64: return 4.0 / 3.0
        case .nds: return 256.0 / 384.0
        case .psp: return 480.0 / 272.0
        }
    }

    /// Hardware refresh rate used for frame pacing until the core reports its own.
    public var nominalFrameRate: Double {
        switch self {
        case .gba: return 16_777_216.0 / 280_896.0 // 59.7275
        case .n64: return 60.0
        case .nds: return 33_513_982.0 / 560_190.0 // 59.8261
        case .psp: return 59.94
        }
    }
}

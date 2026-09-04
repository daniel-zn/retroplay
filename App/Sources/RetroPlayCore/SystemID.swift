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
        case .gba: return ["gba", "agb", "mb", "zip"]
        case .n64: return ["n64", "z64", "v64", "zip"]
        case .nds: return ["nds", "dsi", "zip"]
        case .psp: return ["iso", "cso", "chd", "pbp", "prx", "elf"]
        }
    }
}

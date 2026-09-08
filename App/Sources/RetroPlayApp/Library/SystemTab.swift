import Foundation
import RetroPlayCore

/// Library filter tabs: All + each P0 system.
public enum SystemTab: String, CaseIterable, Identifiable, Sendable {
    case all
    case gba
    case n64
    case nds
    case psp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .gba: return "GBA"
        case .n64: return "N64"
        case .nds: return "NDS"
        case .psp: return "PSP"
        }
    }

    public var systemID: SystemID? {
        switch self {
        case .all: return nil
        case .gba: return .gba
        case .n64: return .n64
        case .nds: return .nds
        case .psp: return .psp
        }
    }
}

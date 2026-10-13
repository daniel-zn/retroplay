// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import RetroPlayCore

/// Library filter tabs: All + each system, grouped by maker and in release order.
public enum SystemTab: String, CaseIterable, Identifiable, Sendable {
    case all
    case nes
    case snes
    case n64
    case gba
    case nds
    case genesis
    case ps1
    case psp
    case atari7800

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .gba: return "GBA"
        case .n64: return "N64"
        case .nds: return "NDS"
        case .psp: return "PSP"
        case .nes: return "NES"
        case .snes: return "SNES"
        case .genesis: return "Genesis"
        case .atari7800: return "7800"
        case .ps1: return "PS1"
        }
    }

    public var systemID: SystemID? {
        switch self {
        case .all: return nil
        case .gba: return .gba
        case .n64: return .n64
        case .nds: return .nds
        case .psp: return .psp
        case .nes: return .nes
        case .snes: return .snes
        case .genesis: return .genesis
        case .atari7800: return .atari7800
        case .ps1: return .ps1
        }
    }
}

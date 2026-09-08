import SwiftUI

/// Dark-first chrome: true black sections, near-black cards.
@available(iOS 18.0, *)
enum RetroPlayTheme {
    static let canvas = Color.black
    static let section = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let cardStroke = Color.white.opacity(0.08)
    static let accent = Color.cyan.opacity(0.85)

    static func systemTint(_ id: SystemID) -> Color {
        switch id {
        case .gba: return Color(red: 0.45, green: 0.55, blue: 0.95)
        case .n64: return Color(red: 0.55, green: 0.85, blue: 0.45)
        case .nds: return Color(red: 0.85, green: 0.45, blue: 0.55)
        case .psp: return Color(red: 0.45, green: 0.75, blue: 0.90)
        }
    }

    static func systemSymbol(_ id: SystemID) -> String {
        switch id {
        case .gba: return "gamecontroller.fill"
        case .n64: return "n.circle.fill"
        case .nds: return "rectangle.split.2x1.fill"
        case .psp: return "ipod"
        }
    }
}

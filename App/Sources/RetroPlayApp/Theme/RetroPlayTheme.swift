import RetroPlayCore
import SwiftUI

/// Adaptive chrome: true black sections in dark; light system backgrounds in light.
@available(iOS 18.0, *)
enum RetroPlayTheme {
    static let accent = Color.cyan.opacity(0.85)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground)
    }

    static func section(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.08)
            : Color(uiColor: .secondarySystemGroupedBackground)
    }

    static func card(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.14)
            : Color(uiColor: .secondarySystemBackground)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .primary
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.45) : .secondary
    }

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

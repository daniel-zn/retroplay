// SPDX-License-Identifier: GPL-3.0-or-later
import RetroPlayCore
import SwiftUI

/// Adaptive chrome: true black sections in dark; light system backgrounds in light.
@available(iOS 18.0, *)
enum RetroPlayTheme {
    static let accent = Color(red: 0.48, green: 0.56, blue: 0.28)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground)
    }

    static func section(for scheme: ColorScheme) -> Color {
        // Dark UI matches Apple Music: full black chrome, not a grey nav band.
        scheme == .dark
            ? Color.black
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

    static func shortName(_ id: SystemID) -> String {
        switch id {
        case .gba: return "GBA"
        case .n64: return "N64"
        case .nds: return "NDS"
        case .psp: return "PSP"
        }
    }

    /// Deep tone used behind label art so white pixel text stays readable.
    static func systemShade(_ id: SystemID) -> Color {
        switch id {
        case .gba: return Color(red: 0.17, green: 0.14, blue: 0.36)
        case .n64: return Color(red: 0.10, green: 0.24, blue: 0.14)
        case .nds: return Color(red: 0.30, green: 0.11, blue: 0.17)
        case .psp: return Color(red: 0.08, green: 0.18, blue: 0.26)
        }
    }

    static func elevatedCard(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.18)
            : Color(uiColor: .systemBackground)
    }
}

/// Springy press feedback for large tappable cards and tiles.
@available(iOS 18.0, *)
struct RetroPlayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Filled olive capsule used for primary actions (Play, Import).
@available(iOS 18.0, *)
struct RetroPlayPrimaryButtonStyle: ButtonStyle {
    var tint: Color = RetroPlayTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroPlayFont.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


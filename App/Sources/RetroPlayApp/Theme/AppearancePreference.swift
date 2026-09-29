// SPDX-License-Identifier: GPL-3.0-or-later
import UIKit
import SwiftUI

/// User-facing appearance. Default is dark for development.
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return .unspecified
        }
    }

    /// Window-level override reaches sheets that are already on screen.
    @MainActor
    func applyToWindows() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
        where scene.session.role == .windowApplication {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = userInterfaceStyle
            }
        }
    }
}

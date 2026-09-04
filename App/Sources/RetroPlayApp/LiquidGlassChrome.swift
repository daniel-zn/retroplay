import SwiftUI

/// Liquid Glass helpers. Package platform remains iOS 18; `#available(iOS 26, *)` gates runtime.
/// Chrome only — keep game list content opaque.
enum LiquidGlassChrome {
    @ViewBuilder
    static func applyToChrome<Content: View>(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension View {
    /// Floating control chrome: Liquid Glass on iOS 26+, material capsule fallback earlier.
    func retroPlayGlassChrome() -> some View {
        LiquidGlassChrome.applyToChrome(self)
    }

    /// Navigation bar material; safe on iOS 18 deployment.
    func retroPlayToolbarGlass() -> some View {
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

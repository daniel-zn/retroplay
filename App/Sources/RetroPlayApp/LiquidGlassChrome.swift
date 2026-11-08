// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Liquid Glass helpers. Package platform remains iOS 18; `#available(iOS 26, *)` gates runtime.
/// Chrome only — keep game list content opaque.
extension View {
    /// A control's surface: interactive Liquid Glass in `shape`, optionally tinted (iOS 26),
    /// else `fallback` drawn behind it.
    @ViewBuilder
    func retroPlayGlass<S: Shape, Fallback: View>(
        _ shape: S,
        tint: Color? = nil,
        interactive: Bool = true,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background { ZStack { fallback() } }
        }
    }

    /// Groups glass controls that sit together (one shared backdrop; shapes `spacing`
    /// apart don't blend into each other).
    @ViewBuilder
    func retroPlayGlassGroup(spacing: CGFloat = 0) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Navigation bar material; safe on iOS 18 deployment.
    func retroPlayToolbarGlass() -> some View {
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

extension View {
    /// Content scrolled under the top bar fades softly under its glass buttons and title (iOS 26's
    /// soft scroll edge effect) rather than the hard style's grey band with a line at its
    /// bottom. On a `NavigationStack`, so it reaches every screen pushed in it.
    @ViewBuilder
    func retroPlayScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

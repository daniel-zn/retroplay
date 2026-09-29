// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import RetroPlayCore

/// Hosts `PlayLoadMenuButton`. SwiftUI `Menu` is intentionally not used here:
/// on iOS 26, `Menu(primaryAction:)` shows long-press rows whose actions do not run.
@available(iOS 18.0, *)
struct PlayLoadMenuControlView: UIViewRepresentable {
    var entries: [SaveStateStore.Entry]
    /// A save / load is running: the button is dimmed and ignores taps and long-presses.
    var busy: Bool
    var onCommand: (PlayLoadCommand) -> Void
    var onImport: () -> Void

    /// Matches the Save tile: the menu caps SwiftUI text at AX1, which UIKit doesn't see,
    /// so cap this font at the size subheadline reaches there.
    private static func titleFont() -> UIFont {
        let font = RetroPlayFont.uiFont(size: 15, textStyle: .subheadline)
        let cap = UIFontMetrics(forTextStyle: .subheadline).scaledValue(
            for: 13,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityMedium)
        )
        return font.pointSize > cap ? font.withSize(cap) : font
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayLoadMenuButton {
        let button = PlayLoadMenuButton()
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.applyCaptionFont(Self.titleFont())
        return button
    }

    func updateUIView(_ button: PlayLoadMenuButton, context: Context) {
        // Frame updates rebuild this view constantly. Only the callbacks and save list
        // change; assigning UIButton.Configuration again would cancel a long-press.
        button.onCommand = onCommand
        button.onImportSave = onImport
        button.setEntries(entries)
        // SwiftUI's .disabled does not reach a UIKit view on its own.
        let enabled = !busy && context.environment.isEnabled
        if button.isEnabled != enabled {
            button.isEnabled = enabled
        }
        let style = button.traitCollection.preferredContentSizeCategory
        if context.coordinator.appliedContentSize != style {
            button.applyCaptionFont(Self.titleFont())
            context.coordinator.appliedContentSize = style
        }
    }

    final class Coordinator {
        var appliedContentSize: UIContentSizeCategory?
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PlayLoadMenuButton,
        context: Context
    ) -> CGSize? {
        // Fill the offered width so Load matches the Save tile beside it; height follows
        // the same rule as the SwiftUI tiles (at least MenuTileButtonStyle.height, taller
        // only when the text needs it) rather than taking all the height on offer.
        let intrinsic = uiView.intrinsicContentSize
        return CGSize(
            width: proposal.width.map { max($0, intrinsic.width) } ?? intrinsic.width,
            height: max(intrinsic.height, MenuTileButtonStyle.height)
        )
    }
}

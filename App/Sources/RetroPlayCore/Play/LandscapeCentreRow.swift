// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// The landscape bottom-centre row, as in portrait: fast-forward, pause and sound as one
/// group in the middle, the system's small buttons (SELECT, START, the 7800's switches) split
/// either side of it. It sits between the two thumb columns and below a fitted picture.
public enum LandscapeCentreRow {
    /// The small buttons either side: the first half (rounded down) on the left, the rest on
    /// the right, in order — SELECT | START; START alone goes right; SELECT | PAUSE RESET.
    public static func split<T>(_ buttons: [T]) -> (left: [T], right: [T]) {
        let leftCount = buttons.count / 2
        return (Array(buttons.prefix(leftCount)), Array(buttons.dropFirst(leftCount)))
    }

    /// One way to draw the row; the first that fits between the columns is used.
    public struct Style: Equatable, Sendable {
        /// Each of the three round buttons.
        public let buttonWidth: CGFloat
        /// Between the three.
        public let buttonSpacing: CGFloat
        /// Between the group and the small buttons, and between those.
        public let sideSpacing: CGFloat
        /// The small buttons' size against their usual one.
        public var buttonScale: CGFloat = 1
    }

    /// Roomiest first.
    public static let styles: [Style] = [
        Style(buttonWidth: 48, buttonSpacing: 10, sideSpacing: 14),
        Style(buttonWidth: 40, buttonSpacing: 8, sideSpacing: 8),
        Style(buttonWidth: 34, buttonSpacing: 6, sideSpacing: 4),
        // Three switches (the 7800's) on a narrow phone: smaller small buttons, still centred.
        Style(buttonWidth: 34, buttonSpacing: 6, sideSpacing: 4, buttonScale: 0.75),
    ]

    /// The row's height: the round buttons' 32 pt, or a small button's touch area.
    public static let height: CGFloat = 44
    /// Gap under the row, above the screen's bottom edge.
    public static let bottomPadding: CGFloat = 4

    /// Room between the thumb columns (each `columnWidth`, `edgeInset` from the side).
    public static func gap(width: CGFloat, columnWidth: CGFloat, edgeInset: CGFloat) -> CGFloat {
        max(0, width - 2 * (columnWidth + edgeInset))
    }

    /// Height a fitted picture leaves free at the bottom of the safe area for the row, which
    /// also uses the home-indicator strip below it (`bottomSafeArea`).
    public static func pictureReserve(bottomSafeArea: CGFloat) -> CGFloat {
        max(0, height + bottomPadding - bottomSafeArea)
    }
}

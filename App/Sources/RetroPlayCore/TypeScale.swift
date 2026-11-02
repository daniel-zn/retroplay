// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// RetroPlay's one typeface: Game Of Squids by Darrell Flood (free for all use; see
/// GameOfSquids-SOURCE.md), one weight, bundled unchanged in AppHost/Supporting and listed in
/// Info.plist's UIAppFonts.
public enum RetroPlayTypeface {
    public static let family = "Game Of Squids"
    public static let postScriptName = "GameOfSquids"
    /// The file as the designer ships it (the license forbids reformatting it).
    public static let fileName = "GameOfSquids-1GMVL.ttf"
    /// The face's capitals are its regular letters; its lowercase are stretched display
    /// variants ("o" is a circle). Every text is shown in capitals.
    public static let showsCapitalsOnly = true
    /// Extra space between letters: none, the face is already set wide.
    public static let tracking: CGFloat = 0
}

/// The type scale every text in the app is set from (RetroPlayFont builds the fonts, scaled
/// with Dynamic Type from the system style named here). Game Of Squids has one weight, sets
/// about a third wider than a text face and its capitals are 0.63 em tall, so each style sits a
/// few points under Apple's, and the hierarchy comes from size and colour (no bold: iOS would
/// fake it). Nothing goes under 11 pt.
public struct RetroPlayTextStyle: Sendable, Equatable {
    /// The system text style the size scales with.
    public enum Relative: Sendable, CaseIterable {
        case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2
    }

    public let name: String
    public let size: CGFloat
    public let relativeTo: Relative

    public init(name: String, size: CGFloat, relativeTo: Relative) {
        self.name = name
        self.size = size
        self.relativeTo = relativeTo
    }

    public static let largeTitle = Self(name: "largeTitle", size: 28, relativeTo: .largeTitle)
    public static let title = Self(name: "title", size: 23, relativeTo: .title)
    public static let title2 = Self(name: "title2", size: 19, relativeTo: .title2)
    public static let title3 = Self(name: "title3", size: 17, relativeTo: .title3)
    // Headline is a size above body (no bold to set it apart).
    public static let headline = Self(name: "headline", size: 15, relativeTo: .headline)
    public static let body = Self(name: "body", size: 14, relativeTo: .body)
    public static let callout = Self(name: "callout", size: 13.5, relativeTo: .callout)
    public static let subheadline = Self(name: "subheadline", size: 13, relativeTo: .subheadline)
    public static let footnote = Self(name: "footnote", size: 12, relativeTo: .footnote)
    public static let caption = Self(name: "caption", size: 11.5, relativeTo: .caption)
    public static let caption2 = Self(name: "caption2", size: 11, relativeTo: .caption2)

    public static let all: [RetroPlayTextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]
}

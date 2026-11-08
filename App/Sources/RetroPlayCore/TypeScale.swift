// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// RetroPlay's one typeface: You're Gone by Ray Larabie (CC0; see YoureGone-SOURCE.md), its
/// upright weight, bundled unchanged in AppHost/Supporting and listed in Info.plist's UIAppFonts.
/// A capitals face: its lowercase keys draw the capitals, so text is shown as written (no case
/// change) and still reads in capitals.
public enum RetroPlayTypeface {
    public static let family = "You're Gone"
    public static let postScriptName = "YoureGone-Regular"
    public static let fileName = "YoureGone-Regular.otf"
    /// Extra space between letters: none, the face is spaced for text already.
    public static let tracking: CGFloat = 0
}

/// The type scale every text in the app is set from (RetroPlayFont builds the fonts, scaled
/// with Dynamic Type from the system style named here). You're Gone's capitals are 0.74 em tall
/// (taller than the system face's) and all text is in capitals, so each style sits a little
/// under Apple's; the hierarchy comes from size and colour (no bold: iOS would fake it). Nothing
/// goes under 11 pt.
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

    public static let largeTitle = Self(name: "largeTitle", size: 30, relativeTo: .largeTitle)
    public static let title = Self(name: "title", size: 25, relativeTo: .title)
    public static let title2 = Self(name: "title2", size: 20, relativeTo: .title2)
    public static let title3 = Self(name: "title3", size: 18, relativeTo: .title3)
    // Headline is a size above body (no bold to set it apart).
    public static let headline = Self(name: "headline", size: 16, relativeTo: .headline)
    public static let body = Self(name: "body", size: 15, relativeTo: .body)
    public static let callout = Self(name: "callout", size: 14, relativeTo: .callout)
    public static let subheadline = Self(name: "subheadline", size: 13.5, relativeTo: .subheadline)
    public static let footnote = Self(name: "footnote", size: 12.5, relativeTo: .footnote)
    public static let caption = Self(name: "caption", size: 11.5, relativeTo: .caption)
    public static let caption2 = Self(name: "caption2", size: 11, relativeTo: .caption2)

    public static let all: [RetroPlayTextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]
}

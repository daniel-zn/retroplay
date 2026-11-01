// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// RetroPlay's one typeface: Hydrogen Whiskey by Ray Larabie (CC0), one weight, bundled in
/// AppHost/Supporting and listed in Info.plist's UIAppFonts.
public enum RetroPlayTypeface {
    public static let family = "Hydrogen Whiskey"
    public static let postScriptName = "HydrogenWhiskey-Regular"
    public static let fileName = "HydrogenWhiskey-Regular.otf"
    /// Extra space between letters for every text, in points at the default text size (it
    /// grows with Dynamic Type): the face is set tight for display sizes, and this keeps small
    /// text open (about 5% of a 12 pt letter, 2% of a 30 pt one).
    public static let tracking: CGFloat = 0.6
}

/// The type scale every text in the app is set from (RetroPlayFont builds the fonts, scaled
/// with Dynamic Type from the system style named here). Hydrogen Whiskey has one weight and
/// draws lowercase as small capitals at full cap height, so it reads large for its size: each
/// style sits a point or two under Apple's, and the hierarchy comes from size and colour (no
/// bold: iOS would fake it). Nothing goes under 11 pt, where its letters start to close up.
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

    public static let largeTitle = Self(name: "largeTitle", size: 31, relativeTo: .largeTitle)
    public static let title = Self(name: "title", size: 25, relativeTo: .title)
    public static let title2 = Self(name: "title2", size: 21, relativeTo: .title2)
    public static let title3 = Self(name: "title3", size: 19, relativeTo: .title3)
    // Headline is a size above body (no bold to set it apart).
    public static let headline = Self(name: "headline", size: 17, relativeTo: .headline)
    public static let body = Self(name: "body", size: 15.5, relativeTo: .body)
    public static let callout = Self(name: "callout", size: 14.5, relativeTo: .callout)
    public static let subheadline = Self(name: "subheadline", size: 13.5, relativeTo: .subheadline)
    public static let footnote = Self(name: "footnote", size: 12.5, relativeTo: .footnote)
    public static let caption = Self(name: "caption", size: 12, relativeTo: .caption)
    public static let caption2 = Self(name: "caption2", size: 11, relativeTo: .caption2)

    public static let all: [RetroPlayTextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]
}

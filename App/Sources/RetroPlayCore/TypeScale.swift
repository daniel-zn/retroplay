// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// RetroPlay's one typeface: Oxanium (SIL OFL 1.1), bundled as static weights in
/// AppHost/Supporting and listed in Info.plist's UIAppFonts.
public enum RetroPlayTypeface {
    public static let family = "Oxanium"

    public enum Weight: String, CaseIterable, Sendable {
        case regular = "Oxanium-Regular"
        case medium = "Oxanium-Medium"
        case semibold = "Oxanium-SemiBold"
        case bold = "Oxanium-Bold"

        public var postScriptName: String { rawValue }
        public var fileName: String { rawValue + ".ttf" }
    }
}

/// The type scale every text in the app is set from (RetroPlayFont builds the fonts, scaled
/// with Dynamic Type from the system style named here). Oxanium sets about 2-5% wider than
/// the system face and has a little more built-in line spacing, so each size sits about a
/// point under Apple's; small sizes are a weight heavier so the open, squared letters stay
/// solid on dark backgrounds.
public struct RetroPlayTextStyle: Sendable, Equatable {
    /// The system text style the size scales with.
    public enum Relative: Sendable, CaseIterable {
        case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2
    }

    public let name: String
    public let size: CGFloat
    public let weight: RetroPlayTypeface.Weight
    public let relativeTo: Relative

    public init(name: String, size: CGFloat, weight: RetroPlayTypeface.Weight, relativeTo: Relative) {
        self.name = name
        self.size = size
        self.weight = weight
        self.relativeTo = relativeTo
    }

    public static let largeTitle = Self(name: "largeTitle", size: 32, weight: .bold, relativeTo: .largeTitle)
    public static let title = Self(name: "title", size: 26, weight: .semibold, relativeTo: .title)
    public static let title2 = Self(name: "title2", size: 21, weight: .semibold, relativeTo: .title2)
    public static let title3 = Self(name: "title3", size: 19, weight: .semibold, relativeTo: .title3)
    public static let headline = Self(name: "headline", size: 16, weight: .semibold, relativeTo: .headline)
    public static let body = Self(name: "body", size: 16, weight: .regular, relativeTo: .body)
    public static let callout = Self(name: "callout", size: 15, weight: .regular, relativeTo: .callout)
    public static let subheadline = Self(name: "subheadline", size: 14, weight: .medium, relativeTo: .subheadline)
    public static let footnote = Self(name: "footnote", size: 13, weight: .medium, relativeTo: .footnote)
    public static let caption = Self(name: "caption", size: 12, weight: .medium, relativeTo: .caption)
    public static let caption2 = Self(name: "caption2", size: 11, weight: .semibold, relativeTo: .caption2)

    public static let all: [RetroPlayTextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body, .callout, .subheadline, .footnote, .caption, .caption2,
    ]
}

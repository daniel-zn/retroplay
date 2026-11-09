// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import RetroPlayCore
import SwiftUI
import UIKit

/// The app's fonts, all You're Gone Thin, from the one type scale (`RetroPlayTextStyle`): text
/// in its upright, titles in its italic (`titleFace(_:)`, with `retroPlayTitleGlitch`).
/// Every font scales with Dynamic Type from its system text style; the bundled file is
/// registered on first use, and if it's missing the system face stands in at the same style.
/// The face has one weight: no style asks for bold (iOS would thicken the outlines itself).
@available(iOS 18.0, *)
@MainActor
enum RetroPlayFont {
    private static var didAttemptRegistration = false
    private static let name = RetroPlayTypeface.postScriptName

    static var largeTitle: Font { font(.largeTitle) }
    static var title: Font { font(.title) }
    static var title2: Font { font(.title2) }
    static var title3: Font { font(.title3) }
    static var headline: Font { font(.headline) }
    static var body: Font { font(.body) }
    static var callout: Font { font(.callout) }
    static var subheadline: Font { font(.subheadline) }
    static var footnote: Font { font(.footnote) }
    static var caption: Font { font(.caption) }
    static var caption2: Font { font(.caption2) }

    static func font(_ style: RetroPlayTextStyle) -> Font {
        sized(style.size, relativeTo: style.relativeTo.swiftUI)
    }

    /// A title's font: the italic at `style`'s size, scaling as it does (the upright if the
    /// italic is missing).
    static func titleFace(_ style: RetroPlayTextStyle) -> Font {
        registerBundledFont()
        let italic = RetroPlayTypeface.titlePostScriptName
        guard UIFont(name: italic, size: style.size) != nil else { return font(style) }
        return .custom(italic, size: style.size, relativeTo: style.relativeTo.swiftUI)
    }

    /// A size off the scale (drawn labels, controls), still scaling with `relativeTo`.
    static func sized(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        registerBundledFont()
        guard UIFont(name: name, size: size) != nil else { return .system(style) }
        return .custom(name, size: size, relativeTo: style)
    }

    /// A size that doesn't follow Dynamic Type: text drawn into artwork (box art, covers)
    /// that is sized to the art itself.
    static func fixed(_ size: CGFloat) -> Font {
        registerBundledFont()
        guard UIFont(name: name, size: size) != nil else { return .system(size: size) }
        return .custom(name, fixedSize: size)
    }

    static func registerBundledFont() {
        guard !didAttemptRegistration else { return }
        didAttemptRegistration = true
        for (postScript, fileName) in [(name, RetroPlayTypeface.fileName),
                                       (RetroPlayTypeface.titlePostScriptName, RetroPlayTypeface.titleFileName)] {
            guard UIFont(name: postScript, size: 17) == nil else { continue }
            let file = fileName as NSString
            guard let url = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension) else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                NSLog("RetroPlay font registration failed: %@", String(describing: error?.takeRetainedValue()))
            }
        }
    }

    static func uiFont(_ style: RetroPlayTextStyle) -> UIFont {
        uiFont(size: style.size, textStyle: style.relativeTo.uiKit)
    }

    /// A title's font for UIKit (the navigation bar's): the italic, as `titleFace(_:)`.
    static func uiTitleFont(_ style: RetroPlayTextStyle) -> UIFont {
        uiFont(size: style.size, textStyle: style.relativeTo.uiKit, face: RetroPlayTypeface.titlePostScriptName)
    }

    static func uiFont(size: CGFloat, textStyle: UIFont.TextStyle, maximumPointSize: CGFloat? = nil,
                       face: String = RetroPlayTypeface.postScriptName) -> UIFont {
        registerBundledFont()
        guard let base = UIFont(name: face, size: size) ?? UIFont(name: name, size: size) else {
            // preferredFont is already scaled; scaling it again would magnify
            // the fallback twice at non-default Dynamic Type sizes.
            return UIFont.preferredFont(forTextStyle: textStyle)
        }
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maximumPointSize {
            return metrics.scaledFont(for: base, maximumPointSize: maximumPointSize)
        }
        return metrics.scaledFont(for: base)
    }

    /// The letter spacing every text gets (`RetroPlayTypeface.tracking`), grown with Dynamic
    /// Type, for UIKit text attributes.
    static var uiKern: CGFloat { UIFontMetrics.default.scaledValue(for: RetroPlayTypeface.tracking) }

    /// UIKit chrome SwiftUI fonts don't reach: bar buttons, segmented controls, search fields.
    /// (Navigation bar titles: `RetroPlayNavigationBarChrome`.)
    static func applyUIKitAppearance() {
        registerBundledFont()
        let bodyFont = uiFont(.body)
        // Capped near its XXXL size, so a segment's label doesn't truncate.
        let segmentFont = uiFont(size: RetroPlayTextStyle.subheadline.size, textStyle: .subheadline, maximumPointSize: 17)
        for state in [UIControl.State.normal, .highlighted, .disabled, .selected] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: bodyFont, .kern: uiKern], for: state)
            UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentFont, .kern: uiKern], for: state)
        }
        let searchAppearance = UISearchTextField.appearance()
        searchAppearance.font = bodyFont
        searchAppearance.adjustsFontForContentSizeCategory = true
        searchAppearance.defaultTextAttributes[.kern] = uiKern
    }
}

/// The face's letter spacing for every text below, growing with Dynamic Type. Set at each
/// root: the app, and each sheet and full-screen cover.
@available(iOS 18.0, *)
private struct RetroPlayTypography: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var tracking = RetroPlayTypeface.tracking

    func body(content: Content) -> some View {
        content.tracking(tracking)
    }
}

@available(iOS 18.0, *)
extension View {
    func retroPlayTypography() -> some View {
        modifier(RetroPlayTypography())
    }
}

@available(iOS 18.0, *)
extension RetroPlayTextStyle.Relative {
    var swiftUI: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }

    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import RetroPlayCore
import SwiftUI
import UIKit

/// The app's fonts, all Oxanium, from the one type scale (`RetroPlayTextStyle`). Every font
/// scales with Dynamic Type from its system text style; the bundled files are registered on
/// first use, and a missing file falls back to the system face at the same style.
@available(iOS 18.0, *)
@MainActor
enum RetroPlayFont {
    typealias Weight = RetroPlayTypeface.Weight
    private static var didAttemptRegistration = false

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
        custom(style.weight, size: style.size, relativeTo: style.relativeTo.swiftUI)
    }

    /// A size off the scale (drawn labels, controls), still scaling with `relativeTo`.
    static func sized(_ size: CGFloat, weight: Weight = .medium, relativeTo style: Font.TextStyle = .body) -> Font {
        custom(weight, size: size, relativeTo: style)
    }

    /// A size that doesn't follow Dynamic Type: text drawn into artwork (box art, covers)
    /// that is sized to the art itself.
    static func fixed(_ size: CGFloat, weight: Weight = .bold) -> Font {
        registerBundledFont()
        guard UIFont(name: weight.postScriptName, size: size) != nil else {
            return .system(size: size, weight: weight.systemWeight)
        }
        return .custom(weight.postScriptName, fixedSize: size)
    }

    static func registerBundledFont() {
        guard !didAttemptRegistration else { return }
        didAttemptRegistration = true
        for weight in Weight.allCases where UIFont(name: weight.postScriptName, size: 17) == nil {
            guard let url = Bundle.main.url(forResource: weight.rawValue, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                NSLog("RetroPlay font registration failed: %@", String(describing: error?.takeRetainedValue()))
            }
        }
    }

    static func uiFont(_ style: RetroPlayTextStyle) -> UIFont {
        uiFont(size: style.size, weight: style.weight, textStyle: style.relativeTo.uiKit)
    }

    static func uiFont(size: CGFloat, weight: Weight, textStyle: UIFont.TextStyle) -> UIFont {
        registerBundledFont()
        guard let base = UIFont(name: weight.postScriptName, size: size) else {
            // preferredFont is already scaled; scaling it again would magnify
            // the fallback twice at non-default Dynamic Type sizes.
            return UIFont.preferredFont(forTextStyle: textStyle)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }

    /// UIKit chrome SwiftUI fonts don't reach: bar buttons, segmented controls, search fields.
    /// (Navigation bar titles: `RetroPlayNavigationBarChrome`.)
    static func applyUIKitAppearance() {
        registerBundledFont()
        let bodyFont = uiFont(.body)
        let segmentFont = uiFont(.subheadline)
        for state in [UIControl.State.normal, .highlighted, .disabled, .selected] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: bodyFont], for: state)
            UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentFont], for: state)
        }
        let searchAppearance = UISearchTextField.appearance()
        searchAppearance.font = bodyFont
        searchAppearance.adjustsFontForContentSizeCategory = true
    }

    private static func custom(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        registerBundledFont()
        guard UIFont(name: weight.postScriptName, size: size) != nil else {
            return .system(style, weight: weight.systemWeight)
        }
        return .custom(weight.postScriptName, size: size, relativeTo: style)
    }
}

@available(iOS 18.0, *)
extension RetroPlayTypeface.Weight {
    var systemWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
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

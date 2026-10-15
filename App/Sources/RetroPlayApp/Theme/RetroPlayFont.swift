// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import SwiftUI
import UIKit

/// Central font loader. The bundled file is preferred; every lookup has a Dynamic Type fallback.
@available(iOS 18.0, *)
@MainActor
enum RetroPlayFont {
    static let postScriptName = "PressStart2P-Regular"
    static let resourceName = "PressStart2P-Regular"
    /// Press Start 2P reads larger than the system face at the same nominal point size.
    /// Keep the visual correction here so tokens, controls, and UIKit chrome stay aligned.
    static let pointSizeReduction: CGFloat = 3
    private static var didAttemptRegistration = false

    /// Large titles ("RetroPlay", "Search", "Settings"): the pixel face at the system's 34 pt
    /// fills the screen width, so they're set much smaller than other text.
    static let largeTitleSize: CGFloat = 24
    static var largeTitle: Font { sized(largeTitleSize, relativeTo: .largeTitle) }
    static var title3: Font { sized(20, relativeTo: .title3) }
    static var body: Font { sized(17, relativeTo: .body) }
    static var subheadline: Font { sized(15, relativeTo: .subheadline) }
    static var caption: Font { sized(12, relativeTo: .caption) }
    static var caption2: Font { sized(11, relativeTo: .caption2) }

    static func sized(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        swiftUIFont(size: reduced(size), relativeTo: style)
    }

    static func registerBundledFont() {
        guard !didAttemptRegistration else { return }
        didAttemptRegistration = true
        guard UIFont(name: postScriptName, size: 17) == nil,
              let url = Bundle.main.url(forResource: resourceName, withExtension: "ttf")
        else { return }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            NSLog("RetroPlay font registration failed: %@", String(describing: error?.takeRetainedValue()))
        }
    }

    static func uiFont(size: CGFloat, textStyle: UIFont.TextStyle) -> UIFont {
        registerBundledFont()
        guard let base = UIFont(name: postScriptName, size: reduced(size)) else {
            // preferredFont is already scaled; scaling it again would magnify
            // the fallback twice at non-default Dynamic Type sizes.
            return UIFont.preferredFont(forTextStyle: textStyle)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }

    private static func reduced(_ size: CGFloat) -> CGFloat {
        max(8, size - pointSizeReduction)
    }

    static func applyUIKitAppearance() {
        registerBundledFont()
        let bodyFont = uiFont(size: 17, textStyle: .body)
        for state in [UIControl.State.normal, .highlighted, .disabled, .selected] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: bodyFont], for: state)
            UITabBarItem.appearance().setTitleTextAttributes(
                [.font: uiFont(size: 10, textStyle: .caption2)],
                for: state
            )
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.font: uiFont(size: 13, textStyle: .subheadline)],
                for: state
            )
        }
        // The iOS 26 floating tab bar reads UITabBarAppearance, not UITabBarItem's proxy.
        let tabAttributes: [NSAttributedString.Key: Any] = [.font: uiFont(size: 10, textStyle: .caption2)]
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        for layout in [tabAppearance.stackedLayoutAppearance, tabAppearance.inlineLayoutAppearance, tabAppearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = tabAttributes
            layout.selected.titleTextAttributes = tabAttributes
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let searchAppearance = UISearchTextField.appearance()
        searchAppearance.font = bodyFont
        searchAppearance.adjustsFontForContentSizeCategory = true
    }

    private static func swiftUIFont(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        registerBundledFont()
        guard UIFont(name: postScriptName, size: size) != nil else {
            return .system(style)
        }
        return .custom(postScriptName, size: size, relativeTo: style)
    }
}

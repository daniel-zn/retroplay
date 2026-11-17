// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// Navigation bar chrome: clear at the top (the large / custom title shows on the canvas) and
/// iOS's own blurred background once content scrolls under it. Also set
/// `UINavigationBar.appearance()` so it sticks even when the local VC has no nav yet.
@available(iOS 18.0, *)
@MainActor
enum RetroPlayNavigationBarChrome {
    private static var lastAppliedColorScheme: ColorScheme?

    static func apply(colorScheme: ColorScheme, force: Bool = false) {
        if !force, lastAppliedColorScheme == colorScheme { return }
        lastAppliedColorScheme = colorScheme
        let foreground: UIColor =
            colorScheme == .dark ? .white : .label

        // Scrolled: iOS's own bar background, so content blurs under it as everywhere else.
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.shadowColor = .clear
        standard.titleTextAttributes = [
            .foregroundColor: foreground,
            .font: RetroPlayFont.uiTitleFont(.headline),
            .kern: RetroPlayFont.uiKern
        ]
        standard.largeTitleTextAttributes = [
            .foregroundColor: foreground,
            .font: RetroPlayFont.uiLargeTitleFont(),
            .kern: RetroPlayFont.uiKern
        ]
        // The library's game count under its title.
        let secondary = UIColor(RetroPlayTheme.secondaryText(for: colorScheme))
        standard.subtitleTextAttributes = [
            .foregroundColor: secondary,
            .font: RetroPlayFont.uiFont(.caption),
            .kern: RetroPlayFont.uiKern
        ]
        standard.largeSubtitleTextAttributes = [
            .foregroundColor: secondary,
            .font: RetroPlayFont.uiFont(.footnote),
            .kern: RetroPlayFont.uiKern
        ]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.backgroundColor = .clear
        scrollEdge.shadowColor = .clear
        scrollEdge.titleTextAttributes = standard.titleTextAttributes
        scrollEdge.largeTitleTextAttributes = standard.largeTitleTextAttributes
        scrollEdge.subtitleTextAttributes = standard.subtitleTextAttributes
        scrollEdge.largeSubtitleTextAttributes = standard.largeSubtitleTextAttributes

        let applyToBar: (UINavigationBar) -> Void = { bar in
            bar.standardAppearance = standard
            bar.scrollEdgeAppearance = scrollEdge
            bar.compactAppearance = standard
            bar.compactScrollEdgeAppearance = scrollEdge
            // Bar buttons (top-bar icons, back chevrons) in the accent, scrolled or not: a white
            // tint here turned the library's buttons white once the bar collapsed.
            bar.tintColor = UIColor(RetroPlayTheme.accent)
            // Each screen asks for its own title display mode (`retroPlayLargeTitle`).
            bar.isTranslucent = true
        }

        let proxy = UINavigationBar.appearance()
        applyToBar(proxy)

        // Already-created bars (Simulator hot rebuild) need a live walk.
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                applyRecursively(in: window, apply: applyToBar)
            }
        }
    }

    static func applyTitleFonts(to item: UINavigationItem, bar: UINavigationBar) {
        let titleFont = RetroPlayFont.uiTitleFont(.headline)
        let largeTitleFont = RetroPlayFont.uiLargeTitleFont()
        func patched(_ appearance: UINavigationBarAppearance?) -> UINavigationBarAppearance? {
            guard let copy = appearance?.copy() else { return nil }
            copy.titleTextAttributes[.font] = titleFont
            copy.largeTitleTextAttributes[.font] = largeTitleFont
            copy.titleTextAttributes[.kern] = RetroPlayFont.uiKern
            copy.largeTitleTextAttributes[.kern] = RetroPlayFont.uiKern
            copy.subtitleTextAttributes[.font] = RetroPlayFont.uiFont(.caption)
            copy.largeSubtitleTextAttributes[.font] = RetroPlayFont.uiFont(.footnote)
            return copy
        }
        item.standardAppearance = patched(item.standardAppearance ?? bar.standardAppearance)
        item.scrollEdgeAppearance = patched(item.scrollEdgeAppearance ?? bar.scrollEdgeAppearance)
        item.compactAppearance = patched(item.compactAppearance ?? bar.compactAppearance)
        item.compactScrollEdgeAppearance = patched(item.compactScrollEdgeAppearance ?? bar.compactScrollEdgeAppearance)
    }

    private static func applyRecursively(in root: UIView, apply: (UINavigationBar) -> Void) {
        if let bar = root as? UINavigationBar {
            apply(bar)
        }
        for sub in root.subviews {
            applyRecursively(in: sub, apply: apply)
        }
    }
}

@available(iOS 18.0, *)
struct NavigationBarTitleChrome: UIViewControllerRepresentable {
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> TitleFontController {
        TitleFontController()
    }

    func updateUIViewController(_ uiViewController: TitleFontController, context: Context) {
        uiViewController.applyTitleFonts()
        DispatchQueue.main.async { uiViewController.applyTitleFonts() }
        guard context.coordinator.lastColorScheme != colorScheme else { return }
        context.coordinator.lastColorScheme = colorScheme
        RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
    }

    /// SwiftUI gives each screen its own `navigationItem` appearance, which wins
    /// over the bar's, so the bundled title font has to be patched in per item.
    final class TitleFontController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            // SwiftUI rebuilds the item's appearance when Dark/Light changes; patch it again after.
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                DispatchQueue.main.async { self.applyTitleFonts() }
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyTitleFonts()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyTitleFonts()
        }

        func applyTitleFonts() {
            var current: UIViewController? = self
            while let vc = current {
                if let nav = vc.navigationController, nav.viewControllers.contains(vc) {
                    RetroPlayNavigationBarChrome.applyTitleFonts(to: vc.navigationItem, bar: nav.navigationBar)
                    return
                }
                current = vc.parent
            }
        }
    }

    final class Coordinator {
        var lastColorScheme: ColorScheme?
    }
}

@available(iOS 18.0, *)
extension View {
    /// Clear scroll-edge + opaque collapsed bar; white large title on black canvas.
    func retroPlayNavigationTitleChrome(for colorScheme: ColorScheme) -> some View {
        background(NavigationBarTitleChrome(colorScheme: colorScheme))
            .onAppear { RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme) }
            .onChange(of: colorScheme) { _, scheme in
                RetroPlayNavigationBarChrome.apply(colorScheme: scheme)
            }
    }
}


@available(iOS 18.0, *)
extension View {
    /// A screen's title as iOS shows it: large under the bar's buttons, collapsing into the bar
    /// as the page scrolls, and inline in landscape; both in the title italic
    /// (`RetroPlayNavigationBarChrome`; pair with `retroPlayNavigationTitleChrome`). The large
    /// one is the app's own Text in the bar's large-title place (iOS 26's `.largeTitle` item),
    /// so it keeps the title glitch; the bar still collapses it to the inline title.
    func retroPlayLargeTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    RetroPlayLargeTitleText(title: title)
                }
            }
    }
}

/// The large title's text: the italic at `RetroPlayTextStyle.largeTitle` (no larger than its
/// largest size), leading like the bar's own, on one line, with the glitch.
@available(iOS 18.0, *)
private struct RetroPlayLargeTitleText: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        Text(title)
            .font(Font(RetroPlayFont.uiLargeTitleFont(compatibleWith: traits)))
            .kerning(RetroPlayFont.uiKern)
            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
            .lineLimit(1)
            .fixedSize()
            .retroPlayTitleGlitch(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

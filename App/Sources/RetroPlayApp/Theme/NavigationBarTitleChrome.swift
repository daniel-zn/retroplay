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
            .font: RetroPlayFont.uiFont(size: 17, textStyle: .headline)
        ]
        standard.largeTitleTextAttributes = [
            .foregroundColor: foreground,
            .font: RetroPlayFont.uiFont(size: RetroPlayFont.largeTitleSize, textStyle: .largeTitle)
        ]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.backgroundColor = .clear
        scrollEdge.shadowColor = .clear
        scrollEdge.titleTextAttributes = standard.titleTextAttributes
        scrollEdge.largeTitleTextAttributes = standard.largeTitleTextAttributes

        let applyToBar: (UINavigationBar) -> Void = { bar in
            bar.standardAppearance = standard
            bar.scrollEdgeAppearance = scrollEdge
            bar.compactAppearance = standard
            bar.compactScrollEdgeAppearance = scrollEdge
            // Bar buttons (top-bar icons, back chevrons) in the accent, scrolled or not: a white
            // tint here turned the library's buttons white once the bar collapsed.
            bar.tintColor = UIColor(RetroPlayTheme.accent)
            // Do not force prefersLargeTitles here — Library is .inline with a
            // custom scroll title; forcing true reserves a blank large-title inset.
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
        let titleFont = RetroPlayFont.uiFont(size: 17, textStyle: .headline)
        let largeTitleFont = RetroPlayFont.uiFont(size: RetroPlayFont.largeTitleSize, textStyle: .largeTitle)
        func patched(_ appearance: UINavigationBarAppearance?) -> UINavigationBarAppearance? {
            guard let copy = appearance?.copy() else { return nil }
            copy.titleTextAttributes[.font] = titleFont
            copy.largeTitleTextAttributes[.font] = largeTitleFont
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


/// Forces `prefersLargeTitles = false` on the enclosing navigation bar (Library custom title).
@available(iOS 18.0, *)
struct LibraryInlineNavChrome: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let apply: () -> Void = {
            var current: UIViewController? = uiViewController
            while let c = current {
                if let nav = c.navigationController {
                    nav.navigationBar.prefersLargeTitles = false
                    return
                }
                current = c.parent
            }
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }
}

@available(iOS 18.0, *)
extension View {
    func retroPlayLibraryInlineNav() -> some View {
        background(LibraryInlineNavChrome())
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

/// Navigation bar chrome: on iOS 26 no bar of its own, at the top or scrolled: no background,
/// no hairline; content passes under the glass buttons and iOS's scroll edge effect keeps the
/// title readable over it. Before iOS 26 (no scroll edge effect), iOS's own blurred background
/// once content scrolls under it. Also set
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

        // Scrolled: on iOS 26 the scroll edge effect under a clear bar, as Apple's own apps; the
        // default background drew a grey band with a hairline under the collapsed title.
        let standard = UINavigationBarAppearance()
        if #available(iOS 26.0, *) {
            standard.configureWithTransparentBackground()
        } else {
            standard.configureWithDefaultBackground()
        }
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
        let subtitleFont = RetroPlayFont.uiFont(.caption)
        let largeSubtitleFont = RetroPlayFont.uiFont(.footnote)
        /// A copy with the fonts, or nil if it has them already: a new appearance makes the bar
        /// lay its items out again, which strands a popover shown from one of them.
        func patched(_ appearance: UINavigationBarAppearance?) -> UINavigationBarAppearance? {
            guard let appearance,
                  appearance.titleTextAttributes[.font] as? UIFont != titleFont
                    || appearance.largeTitleTextAttributes[.font] as? UIFont != largeTitleFont
                    || appearance.subtitleTextAttributes[.font] as? UIFont != subtitleFont
                    || appearance.largeSubtitleTextAttributes[.font] as? UIFont != largeSubtitleFont
            else { return nil }
            let copy = appearance.copy()
            copy.titleTextAttributes[.font] = titleFont
            copy.largeTitleTextAttributes[.font] = largeTitleFont
            copy.titleTextAttributes[.kern] = RetroPlayFont.uiKern
            copy.largeTitleTextAttributes[.kern] = RetroPlayFont.uiKern
            copy.subtitleTextAttributes[.font] = subtitleFont
            copy.largeSubtitleTextAttributes[.font] = largeSubtitleFont
            return copy
        }
        if let new = patched(item.standardAppearance ?? bar.standardAppearance) { item.standardAppearance = new }
        if let new = patched(item.scrollEdgeAppearance ?? bar.scrollEdgeAppearance) { item.scrollEdgeAppearance = new }
        if let new = patched(item.compactAppearance ?? bar.compactAppearance) { item.compactAppearance = new }
        if let new = patched(item.compactScrollEdgeAppearance ?? bar.compactScrollEdgeAppearance) { item.compactScrollEdgeAppearance = new }
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
    /// What the bar shows that SwiftUI rebuilds the item's appearance for (its subtitle, its
    /// items): a change calls `updateUIViewController`, which patches the fonts in again.
    let content: AnyHashable?

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
    /// The bar's look (`RetroPlayNavigationBarChrome`): no bar of its own on iOS 26; the title
    /// in the app's italic.
    /// `content`: what changes in the bar (its subtitle, an item coming and going); SwiftUI
    /// rebuilds the item's appearance then, and the fonts are patched in again.
    func retroPlayNavigationTitleChrome(for colorScheme: ColorScheme, content: AnyHashable? = nil) -> some View {
        background(NavigationBarTitleChrome(colorScheme: colorScheme, content: content))
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
    /// (`RetroPlayNavigationBarChrome`; pair with `retroPlayNavigationTitleChrome`). Where the
    /// title glitch plays, the large one is the app's own Text in the bar's large-title place
    /// (iOS 26's `.largeTitle` item), still collapsing to the inline title. The bar doesn't
    /// expose that item to VoiceOver, so with VoiceOver (or Reduce Motion, or the glitch off)
    /// it's the bar's own large title, which reads as the screen's heading. `subtitle` goes
    /// under it (`navigationSubtitle`).
    func retroPlayLargeTitle(_ title: String, subtitle: String? = nil) -> some View {
        modifier(RetroPlayLargeTitle(title: title, subtitle: subtitle))
    }
}

@available(iOS 18.0, *)
private struct RetroPlayLargeTitle: ViewModifier {
    let title: String
    let subtitle: String?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glitches: Bool {
        !voiceOver && !reduceMotion && (TitleGlitchLaunch.frame ?? 0) >= 0
    }

    func body(content: Content) -> some View {
        let titled = subtitled(content.navigationTitle(title))
            .navigationBarTitleDisplayMode(.large)
        // Not a toolbar with the item left out: an empty one still takes the bar's own title's
        // place (unread by VoiceOver). Turning VoiceOver or Reduce Motion on builds the screen
        // again.
        if glitches {
            titled.toolbar {
                ToolbarItem(placement: .largeTitle) {
                    RetroPlayLargeTitleText(title: title, hasSubtitle: subtitle?.isEmpty == false)
                }
            }
        } else {
            titled
        }
    }

    @ViewBuilder
    private func subtitled(_ content: some View) -> some View {
        if let subtitle {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
    }
}

/// The large title's text: the italic at `RetroPlayTextStyle.largeTitle` (no larger than its
/// largest size), on one line, with the glitch, where the bar draws its own: the bar hosts the
/// item straight under its buttons, where it leaves room above its own title (more with a
/// subtitle under it), so the text keeps that room, grown with the font. Measured against the
/// bar's own title, at the default and the largest text size
/// (`LargeTitleUITests.testGlitchingTitleSitsWhereTheSystemTitleDoes`).
@available(iOS 18.0, *)
private struct RetroPlayLargeTitleText: View {
    let title: String
    let hasSubtitle: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let font = RetroPlayFont.uiLargeTitleFont(compatibleWith: traits)
        let grown = font.pointSize / RetroPlayFont.uiLargeTitleFont(
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        Text(title)
            .font(Font(font))
            .kerning(RetroPlayFont.uiKern)
            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
            .lineLimit(1)
            .fixedSize()
            .retroPlayTitleGlitch(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ((hasSubtitle ? 21.7 : 8) * grown).rounded())
    }
}

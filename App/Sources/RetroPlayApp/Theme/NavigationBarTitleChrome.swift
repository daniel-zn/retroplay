import SwiftUI
import UIKit

/// Music-style black chrome: opaque SwiftUI `toolbarBackground` paints over the
/// *large* title. Use a clear scroll-edge appearance (title visible at top) and
/// an opaque standard appearance (inline title after scroll). Also set
/// `UINavigationBar.appearance()` so it sticks even when the local VC has no nav yet.
@available(iOS 18.0, *)
enum RetroPlayNavigationBarChrome {
    static func apply(colorScheme: ColorScheme) {
        let background: UIColor =
            colorScheme == .dark ? .black : .systemGroupedBackground
        let foreground: UIColor =
            colorScheme == .dark ? .white : .label

        let standard = UINavigationBarAppearance()
        standard.configureWithOpaqueBackground()
        standard.backgroundColor = background
        standard.shadowColor = .clear
        standard.titleTextAttributes = [.foregroundColor: foreground]
        standard.largeTitleTextAttributes = [.foregroundColor: foreground]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.backgroundColor = .clear
        scrollEdge.shadowColor = .clear
        scrollEdge.titleTextAttributes = [.foregroundColor: foreground]
        scrollEdge.largeTitleTextAttributes = [.foregroundColor: foreground]

        let applyToBar: (UINavigationBar) -> Void = { bar in
            bar.standardAppearance = standard
            bar.scrollEdgeAppearance = scrollEdge
            bar.compactAppearance = standard
            bar.compactScrollEdgeAppearance = scrollEdge
            bar.tintColor = foreground
            bar.prefersLargeTitles = true
            bar.isTranslucent = true
        }

        let proxy = UINavigationBar.appearance()
        applyToBar(proxy)

        // Already-created bars (Simulator hot rebuild / TabView) need a live walk.
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                applyRecursively(in: window, apply: applyToBar)
            }
        }
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

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
        let applyLocal: () -> Void = {
            if let nav = uiViewController.navigationController
                ?? uiViewController.parent?.navigationController
                ?? Self.nearestNavigationController(from: uiViewController) {
                let bar = nav.navigationBar
                // Re-apply via shared helper path (appearance already set globally).
                RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
                _ = bar
            }
        }
        applyLocal()
        DispatchQueue.main.async(execute: applyLocal)
    }

    private static func nearestNavigationController(from vc: UIViewController) -> UINavigationController? {
        var current: UIViewController? = vc
        while let c = current {
            if let nav = c as? UINavigationController { return nav }
            if let nav = c.navigationController { return nav }
            current = c.parent
        }
        if let root = vc.view.window?.rootViewController {
            return findNav(in: root)
        }
        return nil
    }

    private static func findNav(in root: UIViewController) -> UINavigationController? {
        if let nav = root as? UINavigationController { return nav }
        for child in root.children {
            if let found = findNav(in: child) { return found }
        }
        if let presented = root.presentedViewController {
            return findNav(in: presented)
        }
        return nil
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

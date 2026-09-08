import SwiftUI
import UIKit

/// Solid black Music-style chrome can leave the *large* nav title uncolored in SwiftUI.
/// Configure the owning UINavigationController appearances with an explicit title color.
@available(iOS 18.0, *)
struct NavigationBarTitleChrome: UIViewControllerRepresentable {
    let colorScheme: ColorScheme

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let apply: () -> Void = {
            guard let nav = uiViewController.navigationController else { return }
            Self.apply(to: nav, colorScheme: colorScheme)
        }
        apply()
        // Navigation controller may not be attached on the first update.
        DispatchQueue.main.async(execute: apply)
    }

    static func apply(to nav: UINavigationController, colorScheme: ColorScheme) {
        let background: UIColor =
            colorScheme == .dark ? .black : .systemGroupedBackground
        let foreground: UIColor =
            colorScheme == .dark ? .white : .label

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: foreground]
        appearance.largeTitleTextAttributes = [.foregroundColor: foreground]

        let bar = nav.navigationBar
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = foreground
        bar.prefersLargeTitles = true
    }
}

@available(iOS 18.0, *)
extension View {
    /// Forces large + inline nav titles to match canvas (white on black in dark).
    func retroPlayNavigationTitleChrome(for colorScheme: ColorScheme) -> some View {
        background(NavigationBarTitleChrome(colorScheme: colorScheme))
    }
}

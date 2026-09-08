import SwiftUI
import UIKit

/// Detects re-tapping the already-selected tab (Apple Music Search behavior).
@available(iOS 18.0, *)
struct TabBarReselectHandler: UIViewControllerRepresentable {
    var onReselect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onReselect = onReselect
        DispatchQueue.main.async {
            guard let tabBarController = Self.findTabBarController(from: uiViewController) else { return }
            if tabBarController.delegate !== context.coordinator {
                context.coordinator.forwardingDelegate = tabBarController.delegate
                tabBarController.delegate = context.coordinator
            }
        }
    }

    private static func findTabBarController(from viewController: UIViewController) -> UITabBarController? {
        var current: UIViewController? = viewController
        while let c = current {
            if let tab = c as? UITabBarController { return tab }
            if let tab = c.tabBarController { return tab }
            current = c.parent
        }
        var responder: UIResponder? = viewController.view
        while let r = responder {
            if let tab = r as? UITabBarController { return tab }
            responder = r.next
        }
        return nil
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: (Int) -> Void
        weak var forwardingDelegate: UITabBarControllerDelegate?

        init(onReselect: @escaping (Int) -> Void) {
            self.onReselect = onReselect
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            shouldSelect viewController: UIViewController
        ) -> Bool {
            if tabBarController.selectedViewController === viewController,
               let viewControllers = tabBarController.viewControllers,
               let index = viewControllers.firstIndex(of: viewController) {
                onReselect(index)
            }
            return forwardingDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelect viewController: UIViewController
        ) {
            forwardingDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        }
    }
}

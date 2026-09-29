// SPDX-License-Identifier: GPL-3.0-or-later
import RetroPlayApp
import SwiftUI
import UIKit

/// UIKit owns external-display scene creation; the phone's SwiftUI scene remains interactive.
@available(iOS 18.0, *)
@objc(ExternalDisplaySceneDelegate)
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var sceneID: String?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if #available(iOS 27.0, *) {
            // iOS 27+ external display is owned by `retroPlayExternalDisplayAccessory()`.
            return
        }
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalGameDisplayView())
        window.backgroundColor = .black
        self.window = window
        sceneID = session.persistentIdentifier
        Task { @MainActor in
            CastingCoordinator.shared.externalDisplayConnected(sceneID: session.persistentIdentifier)
        }
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if #available(iOS 27.0, *) { return }
        if let sceneID {
            Task { @MainActor in
                CastingCoordinator.shared.externalDisplayDisconnected(sceneID: sceneID)
            }
        }
        sceneID = nil
        window = nil
    }
}

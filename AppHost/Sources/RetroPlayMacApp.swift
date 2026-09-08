import SwiftUI
import RetroPlayCore
import RetroPlayApp

@main
struct RetroPlayMacApp: App {
    init() {
        MGBANativeBootstrap.registerIfAvailable()
        PPSSPPNativeBootstrap.registerIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RetroPlayRootView()
        }
    }
}

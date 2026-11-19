// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore
import RetroPlayApp

@main
struct RetroPlayMacApp: App {
    /// Each system's driver, where its core is linked.
    init() {
        #if RETROPLAY_HAS_MGBA
        NativeDriverRegistry.register(.gba) { MGBANativeDriver() }
        #endif
        #if RETROPLAY_HAS_PPSSPP
        NativeDriverRegistry.register(.psp) { PPSSPPNativeDriver() }
        #endif
        #if RETROPLAY_HAS_N64
        NativeDriverRegistry.register(.n64) { N64NativeDriver() }
        #endif
        #if RETROPLAY_HAS_MELONDS
        NativeDriverRegistry.register(.nds) { MelonDSNativeDriver() }
        #endif
        #if RETROPLAY_HAS_LIBRETRO
        for system in SystemID.allCases where system.libretroCore != nil {
            NativeDriverRegistry.register(system) { LibretroNativeDriver(system: system) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RetroPlayRootView()
                .retroPlayExternalDisplayAccessory()
        }
        .commands { RetroPlayCommands() }
    }
}

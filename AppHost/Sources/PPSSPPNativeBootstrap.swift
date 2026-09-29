// SPDX-License-Identifier: GPL-3.0-or-later
import RetroPlayCore

/// Call from `@main` app init. Registers the driver only when the XCFramework is linked.
public enum PPSSPPNativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_PPSSPP
        NativeDriverRegistry.register(.psp) { PPSSPPNativeDriver() }
        #endif
    }
}

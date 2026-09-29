// SPDX-License-Identifier: GPL-3.0-or-later
import RetroPlayCore

/// Call from `@main` app init. Registers the driver only when the XCFramework is linked.
public enum N64NativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_N64
        NativeDriverRegistry.register(.n64) { N64NativeDriver() }
        #endif
    }
}

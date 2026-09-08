import RetroPlayCore

/// Call from `@main` after linking PPSSPP.xcframework and defining RETROPLAY_HAS_PPSSPP.
public enum PPSSPPNativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_PPSSPP
        PPSSPPNativeRegistry.makeDriver = { PPSSPPNativeDriver() }
        #endif
    }
}

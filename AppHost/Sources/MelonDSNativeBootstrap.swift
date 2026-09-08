import RetroPlayCore

/// Call from `@main` after linking melonDS.xcframework and defining RETROPLAY_HAS_MELONDS.
public enum MelonDSNativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_MELONDS
        MelonDSNativeRegistry.makeDriver = { MelonDSNativeDriver() }
        #endif
    }
}

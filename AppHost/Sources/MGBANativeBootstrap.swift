import RetroPlayCore

/// Call from `@main` app init after the XCFramework is linked and `RETROPLAY_HAS_MGBA` is set.
public enum MGBANativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_MGBA
        MGBANativeRegistry.makeDriver = { MGBANativeDriver() }
        #endif
    }
}

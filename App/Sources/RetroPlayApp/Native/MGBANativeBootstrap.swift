import RetroPlayCore

/// Call once from the iOS app entry (e.g. `init()` of `@main App`) after the XCFramework is linked.
public enum MGBANativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_MGBA
        MGBANativeRegistry.makeDriver = { MGBANativeDriver() }
        #endif
    }
}

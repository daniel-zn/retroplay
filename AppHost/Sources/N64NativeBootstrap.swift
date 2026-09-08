import RetroPlayCore

/// Call from `@main` after linking mupen64plus.xcframework and defining RETROPLAY_HAS_N64.
public enum N64NativeBootstrap {
    public static func registerIfAvailable() {
        #if RETROPLAY_HAS_N64
        N64NativeRegistry.makeDriver = { N64NativeDriver() }
        #endif
    }
}

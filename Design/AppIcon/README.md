# RetroPlay app icon

Flat source art for Xcode App Icon (light / dark) and Apple Icon Composer (Liquid Glass).

- `AppIcon-Light.png` — olive `#7A8F47` background, white PSP silhouette
- `AppIcon-Dark.png` — black background, olive PSP silhouette

Asset catalog: `AppHost/Supporting/Assets.xcassets/AppIcon.appiconset`

## Liquid Glass (Icon Composer)

On Mac with Xcode 26 / Icon Composer:

1. Open Icon Composer.
2. Import the light PNG as the default layer (or separate glyph + fill layers).
3. Add dark appearance override using the dark PNG (or recolor fills).
4. Enable Liquid Glass on the glyph layer; export `RetroPlay.icon` into the Xcode project.

Xcode uses the `.icon` for iOS 26+ and can synthesize older appearances from it.

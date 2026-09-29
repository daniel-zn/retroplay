# RetroPlay app icon

## Flat catalog (ships now)
- `AppIcon-Light.png` — olive `#7A8F47` + white wide PSP
- `AppIcon-Dark.png` — black + olive PSP  
Asset catalog: `AppHost/Supporting/Assets.xcassets/AppIcon.appiconset`

PSP proportions match a UMD-era handheld (wide grips), not a square GBA.

## Liquid Glass — Apple Icon Composer (required for real glass)
Apple’s tool: **Icon Composer** (ships with Xcode 26; also https://developer.apple.com/icon-composer/).

Docs: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer  
WWDC: https://developer.apple.com/videos/play/wwdc2025/361/

### Steps on Mac
1. Xcode → Open Developer Tool → **Icon Composer** (or open `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`).
2. New icon → set canvas iOS → background olive `#7A8F47` for Default; black for Dark appearance.
3. Drag in `layers/01-psp-glyph.svg` (or `.png`). Icon Composer applies Liquid Glass automatically.
4. Tune specular / translucency / shadow if needed. Preview Default + Dark.
5. File → Save as `AppIcon.icon` into the RetroPlay repo (e.g. project root or `AppHost/`).
6. In Xcode target → General → App Icons → set App Icon to `AppIcon` (the `.icon` name). Xcode uses `.icon` for iOS 26+ Liquid Glass and synthesizes older assets.

Do **not** bake fake glass into the PNGs — glass is applied by Icon Composer / the system.

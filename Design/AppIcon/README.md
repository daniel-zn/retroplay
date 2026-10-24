# RetroPlay app icon

A phone in a controller grip, on a pink-to-purple gradient.

## What ships

- `AppIcon.icon` (repo root): the Icon Composer document Xcode builds from (iOS 26+).
  - Background: a linear gradient fill, `#CF386B` → `#94266D`; in Dark appearance `#6B1738` → `#3D0D38`.
  - One layer, `controller.png` (transparent), scaled to 86% so the grips clear the corners, with
    specular highlights and a neutral shadow. iOS draws the mask, glass and tinting itself.
- `AppHost/Supporting/Assets.xcassets/AppIcon.appiconset`: flat 1024 px fallbacks (Light and Dark),
  the same picture composed onto the gradient. Square and opaque: no rounding, the system masks it.

## Files here

- `source.png`: the original artwork (metadata stripped).
- `layers/controller.png`: the controller cut out of it, the layer in `AppIcon.icon`.
- `AppIcon-Light.png`, `AppIcon-Dark.png`: copies of the flat fallbacks.

## Previewing without opening Icon Composer

Icon Composer ships with Xcode and includes a command-line renderer:

```sh
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICTOOL" AppIcon.icon --export-image --output-file preview.png --platform iOS \
  --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark` (add `--tint-color 0.9 --tint-strength 0.7`),
`ClearLight`, `ClearDark`.

To edit by hand, open `AppIcon.icon` in Icon Composer (Xcode → Open Developer Tool → Icon Composer).

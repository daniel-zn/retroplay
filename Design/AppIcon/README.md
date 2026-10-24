# RetroPlay app icon

A phone in a controller grip, seen from below, on a pink-to-purple gradient.

## What ships

- `AppIcon.icon` (repo root): the Icon Composer document Xcode builds from (iOS 26+).
  - Background: a linear gradient fill, `#CF386B` → `#94266D`; in Dark appearance `#6B1738` → `#3D0D38`.
  - The controller in three glass depths, each scaled to 80% so it sits clear of the corners:
    front `controls.png` (sticks, D-pad, buttons), middle `panels.png` + `screen.png` (side panels and
    screen), back `body.png` (the whole grip, with the main shadow). Every layer is glass, so in the
    Clear and Tinted looks each part keeps its own edge instead of fading. iOS draws the mask, glass
    and tinting itself.
- `AppHost/Supporting/Assets.xcassets/AppIcon.appiconset`: flat 1024 px fallbacks (Light and Dark),
  the same picture composed onto the gradient. Square and opaque: no rounding, the system masks it.

## Files here

- `source.png`: the original artwork on white (metadata stripped). New artwork works best on a transparent or plain white background: the object becomes the layer and the colour stays a native fill.
- `layers/controller.png`: the whole controller cut out of it (used for the flat fallbacks).
- `layers/body.png`, `panels.png`, `screen.png`, `controls.png`: the parts split from it by tone and
  position, the layers in `AppIcon.icon`.
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

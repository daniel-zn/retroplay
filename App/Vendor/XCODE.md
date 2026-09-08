# Xcode — drop in `mGBA.xcframework`

## Framework on this Mac (already built)

On Daniel’s Mac mini (2026-09-08), the XCFramework is at:

```text
/Users/danielsmacmini/src/retroplay/App/Vendor/Output/mGBA.xcframework
```

(Not in git. Built with `App/Vendor/build-mgba-ios.sh`, ios-arm64 + simulator. Repo clone was at `bdadd91` when built — pull latest before opening Xcode.)

If you rebuild elsewhere, run `./App/Vendor/build-mgba-ios.sh` so Output/ is populated.

## 1. App target

SwiftPM `App/Package.swift` only ships libraries. Create an **iOS App** in Xcode:

1. File → New → Project → App (iOS), product name **RetroPlay**, interface SwiftUI, language Swift.
2. Add local package: select the `App/` folder (contains `Package.swift`).
3. Link `RetroPlayCore` and `RetroPlayApp`.
4. Ensure app target **also compiles** `Sources/RetroPlayApp/Native/*.swift` (included via the `RetroPlayApp` product if you link that library into the app).

Minimum deployment: **iOS 18**.

Root UI example:

```swift
import SwiftUI
import RetroPlayApp
import RetroPlayCore

@main
struct RetroPlayMacApp: App {
    init() {
        MGBANativeBootstrap.registerIfAvailable()
    }
    var body: some Scene {
        WindowGroup {
            RetroPlayRootView()
        }
    }
}
```

## 2. Add the XCFramework

1. Drag `App/Vendor/Output/mGBA.xcframework` into the **app** target (not only the package).
2. **Do Not Embed** for a static XCFramework.
3. Confirm it appears under Frameworks.

## 3. Bridging header (app target)

Build Settings → **Objective-C Bridging Header**:

```text
Vendor/Bridging/RetroPlay-Bridging-Header.h
```

(Adjust path relative to the `.xcodeproj`. Copy the header into the app group if needed.)

## 4. Swift flag (app target)

Active Compilation Conditions (Debug & Release):

```text
RETROPLAY_HAS_MGBA
```

This compiles the real `MGBANativeDriver` body and makes `registerIfAvailable()` install the driver.

## 5. Smoke test

1. Pull latest `daniel-zn/retroplay` on the Mac.
2. Confirm XCFramework path above (or rebuild).
3. Run app → Import a GBA you own → Play.
4. Expect frames once driver loads; if registration was skipped, error text explains linking/`RETROPLAY_HAS_MGBA`.

## Architecture note

mGBA C types stay out of the Swift package. `MGBACore` talks to `MGBANativeDriving`; the app target supplies `MGBANativeDriver` when the framework + flag are present.

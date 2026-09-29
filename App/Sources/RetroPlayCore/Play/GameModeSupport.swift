// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Apple's iOS 18+ Game Mode is opt-in via Info.plist (`LSSupportsGameMode`) and is engaged by
/// the system when the player is in an eligible full-screen game session. There is no public API
/// to force-enable it or to read whether it is active at runtime.
///
/// Sources:
/// - https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsgamemode
/// - https://developer.apple.com/videos/play/wwdc2025/209/
/// - https://support.apple.com/en-us/105118
public enum GameModeSupport: Sendable {
    /// Matches `LSSupportsGameMode` in AppHost/Supporting/Info.plist.
    public static let plistDeclaresSupport = true

    public static let expectedInfoPlistKeyNames = [
        "LSSupportsGameMode",
        "GCSupportsGameMode",
        "LSApplicationCategoryType",
    ] as [String]

    /// Game Mode requires iOS 18+. RetroPlay's deployment target is iOS 18.
    public static var isPlatformEligible: Bool {
        if #available(iOS 18.0, *) {
            return true
        }
        return false
    }

    /// Documented limitation: only the system toggles Game Mode (Control Center overlay).
    public static let runtimeToggleAvailable = false

    /// Compile-time guard: no private Game Mode runtime framework exists on iOS.
    public static let usesPrivateGameModeAPI = false

    public static let deviceLimitations = """
    Requires iPhone/iPad on iOS 18 or later with a supported title. Game Mode is system-managed: \
    RetroPlay declares LSSupportsGameMode and enters Play; the OS may show a banner when eligible. \
    Players adjust it from Control Center → Game Overlay → Game Mode. There is no public API to \
    query or force Game Mode on/off. Simulator behavior is not representative.
    """

    public static let integrationNotes = """
    Declare LSSupportsGameMode (and public.app-category.games) in Info.plist. Enter Play full-screen; \
    the system may show a Game Mode banner. Players can adjust it from Control Center → Game Overlay → Game Mode. \
    No private APIs or runtime force-enable calls are used.
    """

    /// Test helper: verify an Info.plist dictionary contains the expected Game Mode keys.
    public static func infoPlistMatchesExpectations(_ plist: [String: Any]) -> Bool {
        guard (plist["LSSupportsGameMode"] as? Bool) == true else { return false }
        guard (plist["GCSupportsGameMode"] as? Bool) == true else { return false }
        guard (plist["LSApplicationCategoryType"] as? String) == "public.app-category.games" else { return false }
        return expectedInfoPlistKeyNames.allSatisfy { plist[$0] != nil }
    }
}

/// Lightweight session marker for Play — documents intent; does not call private Game Mode APIs.
@available(iOS 18.0, *)
public enum GameModeSession {
    public static func begin() {
        guard GameModeSupport.isPlatformEligible, GameModeSupport.plistDeclaresSupport else { return }
        guard !GameModeSupport.usesPrivateGameModeAPI else { return }
        NSLog("RP_GAMEMODE session began (system-managed; requires LSSupportsGameMode on device)")
    }

    public static func end() {
        NSLog("RP_GAMEMODE session ended")
    }
}

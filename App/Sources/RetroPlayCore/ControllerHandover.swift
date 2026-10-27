// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What happens when a game controller connects or disconnects mid-game: the touch controls
/// fade out or in, quickly, and the game keeps running (the player picks straight up with
/// whichever they now hold).
public enum ControllerHandover {
    /// Seconds the touch controls take to fade in or out.
    public static let fade: Double = 0.25

    /// Whether losing the controller pauses the game: no, the touch controls take over.
    public static let pausesOnDisconnect = false

    /// Whether the touch controls show: without a controller, or with one when the player
    /// asked for both.
    public static func showsTouchControls(hasController: Bool, touchWithController: Bool) -> Bool {
        !hasController || touchWithController
    }
}

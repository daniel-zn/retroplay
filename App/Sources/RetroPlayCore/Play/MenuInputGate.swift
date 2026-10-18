// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Keeps pause-menu presses out of the game. While the menu is open the game gets no
/// controller input; a button still held when it closes (A on Resume, B to close) stays out
/// until it's let go, so it doesn't land in the game as a press.
public struct MenuInputGate: Sendable {
    public private(set) var isMenuOpen = false
    private var blocked: PadRole = []
    private var latest = PhysicalPadState.neutral

    public init() {}

    /// What the game should see for this controller state.
    public mutating func filter(_ pad: PhysicalPadState) -> PhysicalPadState {
        latest = pad
        // A blocked button is free again once it's been released.
        blocked.formIntersection(pad.roles)
        return passed
    }

    /// Opening blocks everything; closing blocks whatever is still held. Returns what the
    /// game should see now.
    public mutating func setMenuOpen(_ open: Bool) -> PhysicalPadState {
        isMenuOpen = open
        if !open { blocked = latest.roles }
        return passed
    }

    private var passed: PhysicalPadState {
        guard !isMenuOpen else { return .neutral }
        var pad = latest
        pad.roles.subtract(blocked)
        return pad
    }
}

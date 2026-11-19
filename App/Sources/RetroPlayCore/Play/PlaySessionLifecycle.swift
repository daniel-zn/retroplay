// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Monotonic token for async Play boot/teardown. Bump when leaving or restarting so in-flight
/// `boot()` work abandons before assigning a new core.
public struct PlaySessionToken: Sendable, Equatable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public func bumped() -> PlaySessionToken {
        PlaySessionToken(rawValue: rawValue + 1)
    }

    public func isCurrent(live: PlaySessionToken) -> Bool {
        rawValue == live.rawValue
    }
}

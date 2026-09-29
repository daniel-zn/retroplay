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

public enum PlaySessionLifecycle: Sendable {
    public static func bump(_ token: PlaySessionToken) -> PlaySessionToken {
        token.bumped()
    }
}

/// Scene-driven auto-pause while the player backgrounds Play without changing UI playback state.
public enum PlaySceneLifecycle: Sendable {
    public enum Phase: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    public struct Transition: Equatable, Sendable {
        public let shouldPauseCore: Bool
        public let shouldResumeCore: Bool
        public let markPausedForBackground: Bool
        public let clearPausedForBackground: Bool

        public static let noop = Transition(
            shouldPauseCore: false,
            shouldResumeCore: false,
            markPausedForBackground: false,
            clearPausedForBackground: false
        )
    }

    /// Only true backgrounding pauses emulation; transient `.inactive` (Control Center, etc.) does not.
    public static func transition(
        to phase: Phase,
        userPlayback: PlaybackControlState,
        pausedForBackground: Bool
    ) -> Transition {
        switch phase {
        case .background:
            guard userPlayback == .running, !pausedForBackground else { return .noop }
            return Transition(
                shouldPauseCore: true,
                shouldResumeCore: false,
                markPausedForBackground: true,
                clearPausedForBackground: false
            )
        case .active:
            guard pausedForBackground else { return .noop }
            return Transition(
                shouldPauseCore: false,
                shouldResumeCore: userPlayback == .running,
                markPausedForBackground: false,
                clearPausedForBackground: true
            )
        case .inactive:
            return .noop
        }
    }
}

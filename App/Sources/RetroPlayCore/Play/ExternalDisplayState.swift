// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum PhonePlaybackPresentation: Sendable, Equatable {
    case localScreen
    case castingRemote

    public static func resolve(hasActiveGame: Bool, hasExternalDisplay: Bool) -> Self {
        hasActiveGame && hasExternalDisplay ? .castingRemote : .localScreen
    }
}

/// Reconcile stale external-display bookkeeping when scene callbacks are missed.
public enum ExternalDisplayConnectivity: Sendable {
    public static func shouldClearStaleConnection(
        trackedSceneCount: Int,
        connectedScreenCount: Int,
        usesLegacyScreenCount: Bool = true
    ) -> Bool {
        guard usesLegacyScreenCount else { return false }
        return trackedSceneCount > 0 && connectedScreenCount < 2
    }
}

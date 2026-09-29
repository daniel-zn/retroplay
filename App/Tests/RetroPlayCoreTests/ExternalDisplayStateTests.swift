// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class ExternalDisplayStateTests: XCTestCase {
    func testPhoneBecomesRemoteOnlyWithGameAndExternalDisplay() {
        XCTAssertEqual(
            PhonePlaybackPresentation.resolve(hasActiveGame: true, hasExternalDisplay: true),
            .castingRemote
        )
        XCTAssertEqual(
            PhonePlaybackPresentation.resolve(hasActiveGame: false, hasExternalDisplay: true),
            .localScreen
        )
        XCTAssertEqual(
            PhonePlaybackPresentation.resolve(hasActiveGame: true, hasExternalDisplay: false),
            .localScreen
        )
    }

    func testExternalDisplayConnectivityClearsStaleTrackedScenes() {
        XCTAssertTrue(
            ExternalDisplayConnectivity.shouldClearStaleConnection(
                trackedSceneCount: 1,
                connectedScreenCount: 1
            )
        )
        XCTAssertFalse(
            ExternalDisplayConnectivity.shouldClearStaleConnection(
                trackedSceneCount: 1,
                connectedScreenCount: 2
            )
        )
        XCTAssertFalse(
            ExternalDisplayConnectivity.shouldClearStaleConnection(
                trackedSceneCount: 0,
                connectedScreenCount: 1
            )
        )
    }

    func testExternalDisplayConnectivitySkipsLegacyScreenCountOnModernOS() {
        XCTAssertFalse(
            ExternalDisplayConnectivity.shouldClearStaleConnection(
                trackedSceneCount: 1,
                connectedScreenCount: 1,
                usesLegacyScreenCount: false
            )
        )
    }
}

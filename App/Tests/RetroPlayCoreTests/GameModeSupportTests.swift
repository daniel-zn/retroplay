// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class GameModeSupportTests: XCTestCase {
    func testPlistIntegrationIsDeclaredInCode() {
        XCTAssertTrue(GameModeSupport.plistDeclaresSupport)
    }

    func testPlatformEligibilityOnModernSDK() {
        XCTAssertTrue(GameModeSupport.isPlatformEligible)
    }

    func testNoPrivateRuntimeToggleAPI() {
        XCTAssertFalse(GameModeSupport.runtimeToggleAvailable)
    }

    func testIntegrationNotesMentionSystemManagedBehavior() {
        XCTAssertTrue(GameModeSupport.integrationNotes.contains("LSSupportsGameMode"))
        XCTAssertTrue(GameModeSupport.integrationNotes.contains("Control Center"))
    }

    func testNoPrivateGameModeRuntimeAPI() {
        XCTAssertFalse(GameModeSupport.usesPrivateGameModeAPI)
    }

    func testDeviceLimitationsDocumentEligibility() {
        XCTAssertTrue(GameModeSupport.deviceLimitations.contains("iOS 18"))
        XCTAssertTrue(GameModeSupport.deviceLimitations.contains("system-managed"))
        XCTAssertTrue(GameModeSupport.deviceLimitations.contains("Simulator"))
    }

    func testAppHostInfoPlistDeclaresGameModeKeys() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repoRoot.appendingPathComponent("AppHost/Supporting/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertNotNil(plist)
        XCTAssertTrue(GameModeSupport.infoPlistMatchesExpectations(plist ?? [:]))
    }

    @available(iOS 18.0, *)
    func testGameModeSessionBeginIsAvailabilityGuarded() {
        GameModeSession.begin()
        GameModeSession.end()
    }
}

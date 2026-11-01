// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

/// A pick whose access can't be started is reported only when it can't be read without it: a
/// folder the app can already read (its own Documents) needs no access.
final class SecurityScopedAccessTests: XCTestCase {
    func testAReadableFolderWithoutAccessIsNotRefused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let access = SecurityScopedAccess([folder])
        defer { access.stop() }
        XCTAssertEqual(access.refused, [])
    }

    func testAFolderThatCantBeReadIsRefused() throws {
        #if !os(iOS)
        // Outside a sandbox every URL's access starts, so nothing is ever refused.
        throw XCTSkip("Security-scoped access always starts outside the iOS sandbox.")
        #endif
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let access = SecurityScopedAccess([missing])
        defer { access.stop() }
        XCTAssertEqual(access.refused, [missing])
    }
}

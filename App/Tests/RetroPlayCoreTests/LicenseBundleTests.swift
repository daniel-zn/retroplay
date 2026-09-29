// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// The app shows every bundled component's license from AppHost/Supporting/Licenses.
/// A missing or empty text would ship a broken notice, so check the bundle in the repo.
final class LicenseBundleTests: XCTestCase {
    private var licensesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RetroPlayCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("AppHost/Supporting/Licenses", isDirectory: true)
    }

    func testEveryComponentHasANonEmptyLicenseText() throws {
        let data = try Data(contentsOf: licensesDirectory.appendingPathComponent("components.json"))
        let components = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertFalse(components.isEmpty)
        for component in components {
            let name = component["name"] as? String ?? "?"
            for key in ["name", "usedBy", "license", "copyright", "source", "licenseFile"] {
                XCTAssertFalse((component[key] as? String ?? "").isEmpty, "\(name): missing \(key)")
            }
            let file = licensesDirectory.appendingPathComponent(component["licenseFile"] as? String ?? "")
            let text = try? String(contentsOf: file, encoding: .utf8)
            XCTAssertGreaterThan(text?.count ?? 0, 40, "\(name): license text missing or empty")
        }
    }

    func testCoresAndRetroPlayLicenseArePresent() throws {
        let data = try Data(contentsOf: licensesDirectory.appendingPathComponent("components.json"))
        let components = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let groups = Set(components.compactMap { $0["usedBy"] as? String })
        for core in ["GBA core (mGBA)", "DS core (melonDS)", "N64 core (mupen64plus-next)", "PSP core (PPSSPP)"] {
            XCTAssertTrue(groups.contains(core), "no components listed for \(core)")
        }
        let gpl = try String(contentsOf: licensesDirectory.appendingPathComponent("GPL-3.0.txt"), encoding: .utf8)
        XCTAssertTrue(gpl.contains("GNU GENERAL PUBLIC LICENSE") && gpl.contains("Version 3"))
    }
}

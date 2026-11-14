// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

/// RetroPlay's changes to the emulator cores live in App/Vendor/patches. The published source
/// only corresponds to the shipped binaries if every patch is listed in SOURCES.md and applied by
/// fetch-core-sources.sh, so check that in the repo.
final class VendorPatchesTests: XCTestCase {
    private var vendorDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // RetroPlayCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // App
            .appendingPathComponent("Vendor", isDirectory: true)
    }

    private func text(_ name: String) throws -> String {
        try String(contentsOf: vendorDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    func testEveryPatchIsListedAndApplied() throws {
        let sources = try text("SOURCES.md")
        let fetch = try text("fetch-core-sources.sh")
        let patches = try FileManager.default.contentsOfDirectory(atPath: vendorDirectory.appendingPathComponent("patches").path)
            .filter { $0.hasSuffix(".patch") }
        XCTAssertFalse(patches.isEmpty)
        for patch in patches {
            XCTAssertTrue(sources.contains("patches/\(patch)"), "\(patch) is not listed in SOURCES.md")
            XCTAssertTrue(fetch.contains("patches/\(patch)"), "\(patch) is not applied by fetch-core-sources.sh")
        }
    }

    /// PPSSPP's hardware renderers drop mipmaps when a game picks per-pixel (slope) texture LOD,
    /// which made ATV Offroad Fury Pro's terrain flip between dark and light squares. The PSP
    /// core is built with RetroPlay's fix, which samples the mip level per pixel in the shader.
    func testPPSSPPIsBuiltWithTheSlopeLODFix() throws {
        let patch = try text("patches/ppsspp-tex-lod-slope.patch")
        XCTAssertTrue(patch.contains("textureLod(tex, %s.xy, u_mipBias - log2(gl_FragCoord.w))"))
        XCTAssertTrue(patch.contains("Modified by RetroPlay"))
        let fetch = try text("fetch-core-sources.sh")
        XCTAssertTrue(fetch.contains("apply_patch \"$DEST/ppsspp\" \"$HERE/patches/ppsspp-tex-lod-slope.patch\""))
    }
}

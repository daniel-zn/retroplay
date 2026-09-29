// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import XCTest
@testable import RetroPlayCore

final class PPGeAtlasTextTests: XCTestCase {
    /// Ubuntu glyphs measured from `ppge_atlas.meta` hash
    /// `2eadb18c05d8f492b46c23bcbad4f4811c98cf717145536ccfe136787845f2ed`.
    /// Button icons sit in the top-left 512 box; these letters do not.
    private let ubuntuGlyphs: [(String, Int, Int)] = [
        ("S", 893, 1338),
        ("a", 0, 1394),
        ("v", 352, 1372),
        ("e", 438, 1154),
        ("O", 1037, 1224),
        ("K", 822, 1073),
        ("c", 2033, 1155),
    ]

    func testSoftwareClampMisSamplesUtilityTextUnlessTextureWindowsAreEnabled() throws {
        let assets = repoRoot().appendingPathComponent("AppHost/Supporting/assets", isDirectory: true)
        let zim = try Data(contentsOf: assets.appendingPathComponent(PPSSPPHostConfig.ppgeAtlasFileName))
        let meta = assets.appendingPathComponent(PPSSPPHostConfig.ppgeAtlasMetaFileName)
        XCTAssertEqual(try sha256Hex(of: meta), PPSSPPHostConfig.ppgeAtlasMetaSHA256)
        XCTAssertEqual(zim.prefix(4), Data("ZIMG".utf8))
        let width = Int(zim.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        let height = Int(zim.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        XCTAssertEqual(width, 2048)
        XCTAssertEqual(height, 2048)
        XCTAssertTrue(PPSSPPHostConfig.utilityDialogTextIsLegible(atlasWidth: width, atlasHeight: height))
        XCTAssertTrue(PPSSPPHostConfig.utilityDialogTextIsLegible(atlasWidth: 512, atlasHeight: 512))

        for (name, texelX, texelY) in ubuntuGlyphs {
            let glyph = PPGeAtlasText.Glyph(
                texelX: texelX,
                texelY: texelY,
                atlasWidth: width,
                atlasHeight: height
            )
            let atlasTexel = PPGeAtlasText.Sample(x: Float(texelX), y: Float(texelY))
            let clamped = PPGeAtlasText.sample(glyph, atlasWidth: width, atlasHeight: height, textureWindows: false)
            let windowed = PPGeAtlasText.sample(glyph, atlasWidth: width, atlasHeight: height, textureWindows: true)
            XCTAssertNotEqual(
                clamped,
                atlasTexel,
                "\(name) is outside the software 512 clamp and would draw the wrong pixels"
            )
            XCTAssertEqual(windowed.x, atlasTexel.x, accuracy: 0.02, "\(name) x")
            XCTAssertEqual(windowed.y, atlasTexel.y, accuracy: 0.02, "\(name) y")
        }

        let bridge = try String(
            contentsOf: repoRoot().appendingPathComponent("AppHost/Sources/RetroPlayPPSSPPBridge.mm"),
            encoding: .utf8
        )
        XCTAssertTrue(
            bridge.contains("rp_ppsspp_enables_software_renderer"),
            "PPGe splits the 2048 atlas into 512 windows only when g_Config.bSoftwareRendering is true"
        )
        XCTAssertTrue(bridge.contains("param.headLess = true"))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sha256Hex(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

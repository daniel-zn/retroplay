// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import XCTest
@testable import RetroPlayCore

/// Every text in the app is set in Game Of Squids: the one bundled face is the one Info.plist
/// lists, it registers, and every style resolves to it (not a fallback, and not a synthesised
/// bold or italic: the face has one weight). Its capitals are the regular letters, so the app
/// shows text in capitals, and the face has the characters the app's own labels use.
final class TypeScaleTests: XCTestCase {
    /// AppHost/Supporting in the checkout, where the app bundles its font from.
    private static let supporting = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RetroPlayCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // App
        .deletingLastPathComponent()   // repository
        .appendingPathComponent("AppHost/Supporting", isDirectory: true)

    override class func setUp() {
        super.setUp()
        let url = supporting.appendingPathComponent(RetroPlayTypeface.fileName) as CFURL
        CTFontManagerRegisterFontsForURL(url, .process, nil)
    }

    func testTheFaceIsBundledAndTheOnlyFontInInfoPlist() throws {
        let plist = try XCTUnwrap(NSDictionary(contentsOf: Self.supporting.appendingPathComponent("Info.plist")))
        let fonts = try XCTUnwrap(plist["UIAppFonts"] as? [String])
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.supporting.appendingPathComponent(RetroPlayTypeface.fileName).path))
        XCTAssertEqual(fonts, [RetroPlayTypeface.fileName])
    }

    func testEveryStyleResolvesToGameOfSquidsWithoutSyntheticTraits() {
        XCTAssertEqual(RetroPlayTypeface.postScriptName, "GameOfSquids")
        for style in RetroPlayTextStyle.all {
            let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, style.size, nil)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Game Of Squids", style.name)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "GameOfSquids", style.name)
            let traits = CTFontGetSymbolicTraits(font)
            XCTAssertFalse(traits.contains(.traitBold), "\(style.name) is bold")
            XCTAssertFalse(traits.contains(.traitItalic), "\(style.name) is italic")
        }
    }

    func testTheScaleRunsFromLargestToSmallestAndStaysReadable() {
        let sizes = RetroPlayTextStyle.all.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
        XCTAssertEqual(Set(sizes).count, sizes.count, "two styles share a size: with one weight they'd look the same")
        XCTAssertGreaterThanOrEqual(sizes.min() ?? 0, 11)
        XCTAssertEqual(Set(RetroPlayTextStyle.all.map(\.relativeTo)).count, RetroPlayTextStyle.all.count, "two styles scale alike")
    }

    func testTextIsShownInCapitals() {
        XCTAssertTrue(RetroPlayTypeface.showsCapitalsOnly, "the face's lowercase are display variants")
    }

    /// The separators and marks the app's own labels use are in the face (the ones it lacks,
    /// "·", "—", "×", aren't used: iOS would draw them from another font).
    func testTheFaceHasTheAppsOwnPunctuation() {
        let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, 17, nil)
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 /.,:;!?'\"()[]-+&%#" {
            var units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), "no “\(character)”")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import XCTest
@testable import RetroPlayCore

/// Every text in the app is set in You're Gone Thin (You're Gone by Ray Larabie, slightly
/// lighter; built in the fonts repo): the one bundled face is the one Info.plist
/// lists, it registers, and every style resolves to it (not a fallback, and not a synthesised
/// bold or italic: the app uses its one upright weight). It's a capitals face (its lowercase
/// keys draw the capitals), so text needs no case change, and it has the characters the app's
/// own labels use, typographic punctuation included.
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
        for file in RetroPlayTypeface.fileNames {
            CTFontManagerRegisterFontsForURL(supporting.appendingPathComponent(file) as CFURL, .process, nil)
        }
    }

    func testTheFaceIsBundledAndTheOnlyFontInInfoPlist() throws {
        let plist = try XCTUnwrap(NSDictionary(contentsOf: Self.supporting.appendingPathComponent("Info.plist")))
        let fonts = try XCTUnwrap(plist["UIAppFonts"] as? [String])
        XCTAssertEqual(RetroPlayTypeface.fileNames, ["YoureGoneThin-Regular.otf", "YoureGoneThin-Italic.otf"])
        for file in RetroPlayTypeface.fileNames {
            XCTAssertTrue(FileManager.default.fileExists(atPath: Self.supporting.appendingPathComponent(file).path), file)
        }
        XCTAssertEqual(fonts, RetroPlayTypeface.fileNames)
    }

    func testEveryStyleResolvesToYoureGoneThinWithoutSyntheticTraits() {
        XCTAssertEqual(RetroPlayTypeface.postScriptName, "YoureGoneThin-Regular")
        XCTAssertEqual(RetroPlayTypeface.fileName, "YoureGoneThin-Regular.otf")
        for style in RetroPlayTextStyle.all {
            let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, style.size, nil)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, "You're Gone Thin", style.name)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "YoureGoneThin-Regular", style.name)
            let traits = CTFontGetSymbolicTraits(font)
            XCTAssertFalse(traits.contains(.traitBold), "\(style.name) is bold")
            XCTAssertFalse(traits.contains(.traitItalic), "\(style.name) is italic")
        }
    }

    /// Titles are set in the family's italic: the real one (its own outlines), not a slanted upright.
    func testTitlesUseTheThinItalic() {
        XCTAssertEqual(RetroPlayTypeface.titlePostScriptName, "YoureGoneThin-Italic")
        let font = CTFontCreateWithName(RetroPlayTypeface.titlePostScriptName as CFString, 34, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "YoureGoneThin-Italic")
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, "You're Gone Thin")
        XCTAssertTrue(CTFontGetSymbolicTraits(font).contains(.traitItalic))
        XCTAssertFalse(CTFontGetSymbolicTraits(font).contains(.traitBold))
        XCTAssertLessThan(CTFontGetSlantAngle(font), -5, "the italic leans right")
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '&:-–—…’" {
            var units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), "no “\(character)” in the italic")
        }
    }

    func testTheScaleRunsFromLargestToSmallestAndStaysReadable() {
        let sizes = RetroPlayTextStyle.all.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
        XCTAssertEqual(Set(sizes).count, sizes.count, "two styles share a size: with one weight they'd look the same")
        XCTAssertGreaterThanOrEqual(sizes.min() ?? 0, 11)
        XCTAssertEqual(Set(RetroPlayTextStyle.all.map(\.relativeTo)).count, RetroPlayTextStyle.all.count, "two styles scale alike")
    }

    /// Lowercase draws the same capitals as uppercase, so text is shown as written (no case
    /// change: VoiceOver reads the words, and system menus keep their own case anyway).
    func testLowercaseDrawsTheCapitals() {
        let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, 17, nil)
        for (lower, upper) in zip("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
            var units = Array(String(lower).utf16) + Array(String(upper).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: 2)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &units, &glyphs, 2), "no “\(lower)”")
            XCTAssertEqual(glyphs[0], glyphs[1], "“\(lower)” isn't drawn as “\(upper)”")
        }
    }

    /// The separators and marks the app's own labels use are in the face, so none is drawn
    /// from another font.
    func testTheFaceHasTheAppsOwnPunctuation() {
        let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, 17, nil)
        for character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 /.,:;!?'\"()[]-+&%#–—·•…×‘’“”é" {
            var units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), "no “\(character)”")
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import XCTest
@testable import RetroPlayCore

/// Every text in the app is set in Hydrogen Whiskey: the one bundled face is the one Info.plist
/// lists, it registers, and every style resolves to it (not a fallback, and not a synthesised
/// bold or italic: the face has one weight).
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

    func testEveryStyleResolvesToHydrogenWhiskeyWithoutSyntheticTraits() {
        XCTAssertEqual(RetroPlayTypeface.postScriptName, "HydrogenWhiskey-Regular")
        for style in RetroPlayTextStyle.all {
            let font = CTFontCreateWithName(RetroPlayTypeface.postScriptName as CFString, style.size, nil)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, "Hydrogen Whiskey", style.name)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "HydrogenWhiskey-Regular", style.name)
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
}

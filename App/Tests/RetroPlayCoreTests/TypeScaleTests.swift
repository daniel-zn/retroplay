// SPDX-License-Identifier: GPL-3.0-or-later
import CoreText
import XCTest
@testable import RetroPlayCore

/// Every text in the app is set in Oxanium: the bundled files are the weights the type scale
/// names, each registers, and every style resolves to Oxanium in its weight (not a fallback).
final class TypeScaleTests: XCTestCase {
    /// AppHost/Supporting in the checkout, where the app bundles its fonts from.
    private static let supporting = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RetroPlayCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // App
        .deletingLastPathComponent()   // repository
        .appendingPathComponent("AppHost/Supporting", isDirectory: true)

    override class func setUp() {
        super.setUp()
        for weight in RetroPlayTypeface.Weight.allCases {
            let url = supporting.appendingPathComponent(weight.fileName) as CFURL
            CTFontManagerRegisterFontsForURL(url, .process, nil)
        }
    }

    func testEveryWeightIsBundledAndListedInInfoPlist() throws {
        let plist = try XCTUnwrap(NSDictionary(contentsOf: Self.supporting.appendingPathComponent("Info.plist")))
        let fonts = try XCTUnwrap(plist["UIAppFonts"] as? [String])
        for weight in RetroPlayTypeface.Weight.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: Self.supporting.appendingPathComponent(weight.fileName).path), weight.fileName)
            XCTAssertTrue(fonts.contains(weight.fileName), "\(weight.fileName) isn't in UIAppFonts: \(fonts)")
        }
        XCTAssertEqual(Set(fonts), Set(RetroPlayTypeface.Weight.allCases.map(\.fileName)), "UIAppFonts lists other fonts")
    }

    func testEveryStyleResolvesToOxaniumInItsWeight() {
        for style in RetroPlayTextStyle.all {
            let font = CTFontCreateWithName(style.weight.postScriptName as CFString, style.size, nil)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, RetroPlayTypeface.family, style.name)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, style.weight.postScriptName, style.name)
        }
    }

    func testTheScaleRunsFromLargestToSmallest() {
        let sizes = RetroPlayTextStyle.all.map(\.size)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
        XCTAssertEqual(Set(RetroPlayTextStyle.all.map(\.relativeTo)).count, RetroPlayTextStyle.all.count, "two styles scale alike")
    }
}

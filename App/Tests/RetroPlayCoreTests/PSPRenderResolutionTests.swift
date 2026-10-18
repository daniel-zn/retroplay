// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics
import IOSurface
import XCTest
@testable import RetroPlayCore

final class PSPRenderResolutionTests: XCTestCase {
    func testFixedChoicesIgnoreTheScreen() {
        let phone = CGSize(width: 2244, height: 1272)
        XCTAssertEqual(PSPRenderResolution.native.scale(forDisplayPixels: phone), 1)
        XCTAssertEqual(PSPRenderResolution.double.scale(forDisplayPixels: phone), 2)
        XCTAssertEqual(PSPRenderResolution.triple.scale(forDisplayPixels: .zero), 3)
    }

    func testAutoRoundsThePictureSizeToTheNearestMultiple() {
        // iPhone 16 Pro, portrait: the picture is the screen's width, 1206 px (2.5×).
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 1206, height: 683)), 3)
        // iPhone 16 Pro Max landscape, full height: 1320 px tall is 4.85 × 272.
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 2329, height: 1320)), 5)
        // Smaller picture between the landscape control columns.
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 1500, height: 850)), 3)
        // Tiny picture (a split-view thumbnail) never goes below native.
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 200, height: 113)), 1)
    }

    func testAutoUsesTheMoreStretchedAxisForFill() {
        // Fill mode crops: a picture 1320 tall but only 1600 wide is still sharp at 5×.
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 1600, height: 1320)), 5)
    }

    func testAutoIsCappedAndHasAFallback() {
        // A 4K TV over AirPlay.
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: CGSize(width: 3840, height: 2160)), 5)
        XCTAssertEqual(PSPRenderResolution.auto.scale(forDisplayPixels: .zero), PSPRenderResolution.autoFallbackScale)
    }

    func testSavedSettingReadsBackAndUnknownValuesAreAuto() {
        let defaults = UserDefaults(suiteName: "PSPRenderResolutionTests")!
        defer { defaults.removePersistentDomain(forName: "PSPRenderResolutionTests") }
        XCTAssertEqual(PSPRenderResolution.current(defaults), .auto)
        defaults.set(2, forKey: PSPRenderResolution.defaultsKey)
        XCTAssertEqual(PSPRenderResolution.current(defaults), .double)
        defaults.set(42, forKey: PSPRenderResolution.defaultsKey)
        XCTAssertEqual(PSPRenderResolution.current(defaults), .auto)
    }
}

final class VideoFrameStoreTests: XCTestCase {
    func testGPUFramesArePublishedAsSurfaces() throws {
        let store = VideoFrameStore()
        let surface = try XCTUnwrap(IOSurface(properties: [
            .width: 480, .height: 272, .bytesPerElement: 4, .pixelFormat: UInt32(0x42475241),  // 'BGRA'
        ]))
        store.publish(surface: surface)
        let frame = try XCTUnwrap(store.latest(newerThan: 0))
        XCTAssertTrue(frame.contents === surface)
        XCTAssertEqual(store.frameCount, 1)
        XCTAssertNil(store.latest(newerThan: frame.sequence))
    }

    func testCPUFramesStillPublishAsImages() throws {
        let store = VideoFrameStore()
        let buffer = VideoFrameBuffer()
        _ = buffer.prepare(width: 4, height: 2)
        store.publish(buffer)
        let frame = try XCTUnwrap(store.latest(newerThan: 0))
        XCTAssertEqual(CFGetTypeID(frame.contents), CGImage.typeID)
    }

    func testLargestDisplayWinsAndRemovedScreensStopCounting() {
        let store = VideoFrameStore()
        let phone = NSObject(), tv = NSObject()
        XCTAssertEqual(store.largestDisplaySize, .zero)
        store.setDisplaySize(CGSize(width: 1206, height: 683), for: phone)
        store.setDisplaySize(CGSize(width: 1920, height: 1080), for: tv)
        XCTAssertEqual(store.largestDisplaySize, CGSize(width: 1920, height: 1080))
        store.removeDisplay(tv)
        XCTAssertEqual(store.largestDisplaySize, CGSize(width: 1206, height: 683))
        store.setDisplaySize(.zero, for: phone)
        XCTAssertEqual(store.largestDisplaySize, .zero)
    }
}

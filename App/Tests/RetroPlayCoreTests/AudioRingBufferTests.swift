// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class AudioRingBufferTests: XCTestCase {
    func testWriteReadWrapsAround() {
        let ring = AudioRingBuffer(capacity: 64)
        var frames = [Int16](repeating: 0, count: 48 * 2)
        for i in 0..<48 { frames[i * 2] = Int16(i); frames[i * 2 + 1] = Int16(-i) }
        XCTAssertEqual(frames.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 48) }, 48)
        ring.consume(40)
        XCTAssertEqual(ring.availableFrames, 8)
        XCTAssertEqual(frames.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 48) }, 48)
        XCTAssertEqual(ring.availableFrames, 56)
        // Oldest remaining frame is #40 of the first batch; #8 of the backlog wraps.
        XCTAssertEqual(ring.peek(0).left, 40)
        XCTAssertEqual(ring.peek(8).left, 0)
        XCTAssertEqual(ring.peek(8 + 30).right, -30)
    }

    func testOverflowDropsNewest() {
        let ring = AudioRingBuffer(capacity: 64)
        let frames = [Int16](repeating: 1, count: 100 * 2)
        XCTAssertEqual(frames.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 100) }, 64)
        XCTAssertEqual(ring.availableFrames, 64)
    }

    func testRenderResamplesAndPrimes() {
        let ring = AudioRingBuffer(capacity: 16_384)
        let state = AudioRenderState(ring: ring, outputRate: 48_000)
        state.sourceRateBits.store(Double(48_000).bitPattern, ordering: .relaxed)
        var left = [Float](repeating: 1, count: 256)
        var right = [Float](repeating: 1, count: 256)

        // Not primed yet: silence, nothing consumed.
        let silent = left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in state.render(frameCount: 256, left: l.baseAddress!, right: r.baseAddress!) }
        }
        XCTAssertTrue(silent)
        XCTAssertEqual(left[0], 0)

        let frames = [Int16](repeating: 16_384, count: 4_000 * 2)
        _ = frames.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: 4_000) }
        _ = left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in state.render(frameCount: 256, left: l.baseAddress!, right: r.baseAddress!) }
        }
        XCTAssertEqual(left[100], 0.5, accuracy: 1e-4)
        XCTAssertEqual(right[255], 0.5, accuracy: 1e-4)
        XCTAssertLessThan(ring.availableFrames, 4_000)
    }
}

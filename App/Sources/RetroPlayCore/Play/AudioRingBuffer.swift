// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Synchronization

/// Lock-free single-producer / single-consumer ring of interleaved stereo Int16 frames.
///
/// Producer: the emulation thread. Consumer: the realtime audio render thread,
/// which must never block on a lock held by the emulator.
public final class AudioRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Int16>
    /// Total frames ever written / read. Indices wrap with `% capacity`.
    private let writeCount = Atomic<Int>(0)
    private let readCount = Atomic<Int>(0)

    /// `capacity` is in stereo frames.
    public init(capacity: Int) {
        self.capacity = max(64, capacity)
        storage = .allocate(capacity: self.capacity * 2)
        storage.initialize(repeating: 0, count: self.capacity * 2)
    }

    deinit {
        storage.deallocate()
    }

    /// Frames ready to read (consumer view).
    public var availableFrames: Int {
        writeCount.load(ordering: .acquiring) - readCount.load(ordering: .relaxed)
    }

    /// Producer: append frames. Frames that do not fit are dropped (newest lost),
    /// which keeps latency bounded if the output stalls.
    @discardableResult
    public func write(_ frames: UnsafePointer<Int16>, count: Int) -> Int {
        let written = writeCount.load(ordering: .relaxed)
        let read = readCount.load(ordering: .acquiring)
        let free = capacity - (written - read)
        let n = min(max(0, count), free)
        guard n > 0 else { return 0 }
        var start = written % capacity
        var remaining = n
        var src = frames
        while remaining > 0 {
            let chunk = min(remaining, capacity - start)
            (storage + start * 2).update(from: src, count: chunk * 2)
            src += chunk * 2
            remaining -= chunk
            start = 0
        }
        writeCount.store(written + n, ordering: .releasing)
        return n
    }

    /// Consumer: peek frame `offset` frames past the read head. Caller guarantees `offset < availableFrames`.
    @inline(__always)
    public func peek(_ offset: Int) -> (left: Int16, right: Int16) {
        let index = ((readCount.load(ordering: .relaxed) + offset) % capacity) * 2
        return (storage[index], storage[index + 1])
    }

    /// Consumer: drop `count` frames from the head.
    public func consume(_ count: Int) {
        let n = min(max(0, count), availableFrames)
        guard n > 0 else { return }
        readCount.store(readCount.load(ordering: .relaxed) + n, ordering: .releasing)
    }

    /// Producer-side reset is unsafe while the consumer runs; only call when output is stopped.
    public func reset() {
        readCount.store(writeCount.load(ordering: .acquiring), ordering: .releasing)
    }
}

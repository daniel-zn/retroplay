// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Latest input from the UI thread, read by the emulation thread once per frame.
final class InputMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = EmulatorInputState.neutral

    func store(_ input: EmulatorInputState) {
        lock.lock()
        value = input
        lock.unlock()
    }

    func load() -> EmulatorInputState {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// One running game on the emulation thread. Every member is thread-confined to
/// `EmulationThread`; the UI talks to it only through `NativeEmulatorCore`.
final class EmulationSession: @unchecked Sendable {
    let driver: any NativeEmulatorDriver
    let video: VideoFrameStore
    let input: InputMailbox
    let audio: AudioOutput?

    private(set) var isStarted = false
    private var isTornDown = false
    var isPaused = false
    var fastForward = false {
        didSet {
            if fastForward != oldValue { driver.setFastForward(fastForward) }
        }
    }
    var audioEnabled = true
    var respectSilentSwitch = false

    /// Monotonic nanoseconds at which the next frame is due.
    private(set) var nextDeadline: UInt64 = 0
    private var frameInterval: UInt64
    private var lastSampleRate: Double
    private var framesSinceFlush = 0
    private let frameBuffer = VideoFrameBuffer()
    private let audioScratchFrames = 4096
    private let audioScratch: UnsafeMutablePointer<Int16>

    /// Frames emulated per tick while fast-forwarding.
    static let fastForwardMultiplier = 3
    /// Battery saves are flushed about every 3 seconds of play (drivers skip unchanged data).
    private static let flushIntervalFrames = 180

    init(driver: any NativeEmulatorDriver, video: VideoFrameStore, input: InputMailbox) {
        self.driver = driver
        self.video = video
        self.input = input
        let rate = driver.frameRate > 1 ? driver.frameRate : 60
        frameInterval = UInt64(1_000_000_000 / rate)
        lastSampleRate = driver.audioSampleRate
        audio = lastSampleRate > 0 ? AudioOutput(sourceRate: lastSampleRate) : nil
        audioScratch = .allocate(capacity: audioScratchFrames * 2)
        driver.attachVideo(video)
    }

    deinit {
        audioScratch.deallocate()
    }

    var isRunnable: Bool { isStarted && !isPaused }

    func start() {
        isStarted = true
        isPaused = false
        resetClock()
        applyAudioState()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            audio?.pause()
            driver.flushSaveData()
            driver.willSuspend()
        } else {
            resetClock()
            applyAudioState()
        }
    }

    func applyAudioState() {
        guard let audio else { return }
        audio.setMuted(!audioEnabled || fastForward)
        if isStarted && !isPaused {
            audio.start(respectSilentSwitch: respectSilentSwitch)
        }
    }

    func resetClock() {
        nextDeadline = DispatchTime.now().uptimeNanoseconds
    }

    func tick() {
        driver.setInput(input.load())
        let steps = fastForward ? Self.fastForwardMultiplier : 1
        for _ in 0..<steps {
            driver.runFrame()
            drainAudio(discard: fastForward || !audioEnabled)
        }
        if driver.copyVideo(into: frameBuffer) {
            video.publish(frameBuffer)
        }

        let rate = driver.audioSampleRate
        if rate != lastSampleRate {
            lastSampleRate = rate
            audio?.setSourceRate(rate)
        }

        framesSinceFlush += 1
        if framesSinceFlush >= Self.flushIntervalFrames {
            framesSinceFlush = 0
            driver.flushSaveData()
        }

        nextDeadline &+= frameInterval
        let now = DispatchTime.now().uptimeNanoseconds
        // More than ~4 frames behind (slow device, debugger, backgrounding): resync
        // instead of running a burst of frames to "catch up".
        if now > nextDeadline &+ frameInterval &* 4 {
            nextDeadline = now
        }
    }

    private func drainAudio(discard: Bool) {
        while true {
            let count = driver.readAudio(into: audioScratch, maxFrames: audioScratchFrames)
            if count <= 0 { break }
            if !discard {
                audio?.ring.write(audioScratch, count: count)
            }
            if count < audioScratchFrames { break }
        }
    }

    /// Idempotent: a session evicted by a newer load may still get its own `stop()`.
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        audio?.stop()
        driver.flushSaveData()
        driver.willSuspend()
        driver.tearDown()
        isStarted = false
    }
}

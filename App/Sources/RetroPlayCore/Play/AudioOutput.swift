// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Synchronization
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Plays core audio from an `AudioRingBuffer` through AVAudioEngine.
///
/// Cores produce audio at their own rate (GBA 32 768 Hz, NDS 48 000 Hz, N64/PSP 44 100 Hz)
/// and at a pace set by the emulation thread's frame timer, which never matches the
/// sound card exactly. The render callback resamples with a small dynamic rate
/// adjustment (±0.5%) that steers the buffer toward a fixed fill level, so the two
/// clocks never drift into crackles (underrun) or growing lag (overrun).
public final class AudioOutput: @unchecked Sendable {
    public let ring: AudioRingBuffer
    private let state: AudioRenderState
    #if canImport(AVFoundation)
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    #endif
    private var observers: [NSObjectProtocol] = []
    private var wantsRunning = false
    #if os(iOS)
    /// Last category applied to the shared session, so resume / fast-forward toggles
    /// do not reconfigure AVAudioSession (each reconfigure can glitch the route).
    private var appliedCategory: AVAudioSession.Category?
    #endif
    /// Engine calls come from the emulation thread and from route/interruption notifications.
    private let lock = NSRecursiveLock()

    /// Output format rate for the source node; the mixer converts to the hardware rate.
    static let outputRate: Double = 48_000

    public init(sourceRate: Double) {
        // ~340 ms of headroom at 48 kHz; the render side keeps it near `targetLatency`.
        ring = AudioRingBuffer(capacity: 16_384)
        state = AudioRenderState(ring: ring, outputRate: AudioOutput.outputRate)
        setSourceRate(sourceRate)
    }

    deinit {
        stop()
    }

    public func setSourceRate(_ rate: Double) {
        state.sourceRateBits.store(max(0, rate).bitPattern, ordering: .relaxed)
    }

    public func setMuted(_ muted: Bool) {
        state.muted.store(muted, ordering: .relaxed)
    }

    /// Start (or restart) output. Safe to call repeatedly.
    public func start(respectSilentSwitch: Bool) {
        lock.lock()
        defer { lock.unlock() }
        wantsRunning = true
        #if canImport(AVFoundation)
        let engineRunning = engine?.isRunning ?? false
        #if os(iOS)
        let category: AVAudioSession.Category = respectSilentSwitch ? .ambient : .playback
        if category != appliedCategory || !engineRunning {
            let session = AVAudioSession.sharedInstance()
            if category != appliedCategory {
                try? session.setCategory(category, mode: .default, options: [.mixWithOthers])
                appliedCategory = category
            }
            try? session.setPreferredIOBufferDuration(0.01)
            try? session.setActive(true)
        }
        #endif
        if engine == nil {
            buildEngine()
        }
        if let engine, !engineRunning {
            engine.prepare()
            try? engine.start()
        }
        #endif
    }

    public func pause() {
        lock.lock()
        defer { lock.unlock() }
        wantsRunning = false
        #if canImport(AVFoundation)
        engine?.pause()
        #endif
        // Output is stopped now, so the reset cannot race the render thread. Dropping the
        // queued audio keeps a blip of pre-pause sound from playing on resume.
        ring.reset()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        wantsRunning = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        #if canImport(AVFoundation)
        engine?.stop()
        if let sourceNode {
            engine?.detach(sourceNode)
        }
        sourceNode = nil
        engine = nil
        #endif
    }

    #if canImport(AVFoundation)
    private func buildEngine() {
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioOutput.outputRate, channels: 2) else {
            return
        }
        let state = self.state
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else {
                return noErr
            }
            let silent = state.render(frameCount: Int(frameCount), left: left, right: right)
            if silent {
                isSilence.pointee = true
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.engine = engine
        self.sourceNode = node

        // Route changes (headphones, AirPlay) and interruptions (calls, Siri) stop the engine.
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.restartIfWanted()
        })
        #if os(iOS)
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            self?.restartIfWanted()
        })
        #endif
    }

    private func restartIfWanted() {
        lock.lock()
        defer { lock.unlock() }
        guard wantsRunning, let engine, !engine.isRunning else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        engine.prepare()
        try? engine.start()
    }
    #endif
}

/// State shared with the realtime render callback. Only atomics cross threads;
/// the interpolation fields are touched by the render thread alone.
final class AudioRenderState: @unchecked Sendable {
    let ring: AudioRingBuffer
    let outputRate: Double
    let sourceRateBits = Atomic<UInt64>(0)
    let muted = Atomic<Bool>(false)

    private var fraction: Double = 0
    private var primed = false

    init(ring: AudioRingBuffer, outputRate: Double) {
        self.ring = ring
        self.outputRate = outputRate
    }

    /// Fill `frameCount` output frames. Returns true when the whole block is silence.
    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) -> Bool {
        let sourceRate = Double(bitPattern: sourceRateBits.load(ordering: .relaxed))
        var available = ring.availableFrames
        guard sourceRate > 0, !muted.load(ordering: .relaxed) else {
            ring.consume(available)
            primed = false
            fill(left, right, from: 0, to: frameCount)
            return true
        }

        // Aim for ~50 ms queued: enough to absorb frame-timer jitter, low enough to feel instant.
        let target = max(256, Int(sourceRate * 0.05))
        if !primed {
            guard available >= target else {
                fill(left, right, from: 0, to: frameCount)
                return true
            }
            primed = true
            fraction = 0
        }
        if available > target * 3 {
            // A stall let audio pile up; skip ahead instead of playing it late forever.
            ring.consume(available - target)
            available = target
        }

        let error = max(-1, min(1, Double(available - target) / Double(target)))
        let step = sourceRate / outputRate * (1 + 0.005 * error)
        let scale: Float = 1.0 / 32768.0
        var consumed = 0
        var index = 0
        while index < frameCount {
            guard consumed + 1 < available else {
                // Underrun: go quiet and wait to refill rather than stutter.
                primed = false
                break
            }
            let a = ring.peek(consumed)
            let b = ring.peek(consumed + 1)
            let t = Float(fraction)
            let al = Float(a.left), ar = Float(a.right)
            left[index] = (al + (Float(b.left) - al) * t) * scale
            right[index] = (ar + (Float(b.right) - ar) * t) * scale
            fraction += step
            let whole = Int(fraction)
            consumed += whole
            fraction -= Double(whole)
            index += 1
        }
        ring.consume(min(consumed, available))
        if index < frameCount {
            fill(left, right, from: index, to: frameCount)
        }
        return false
    }

    private func fill(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, from: Int, to: Int) {
        guard to > from else { return }
        (left + from).update(repeating: 0, count: to - from)
        (right + from).update(repeating: 0, count: to - from)
    }
}

import Foundation

/// Drives `runFrame`-style ticks. Native mGBA will call into this from a display link on device.
public protocol CoreRunLoopDriving: AnyObject {
    func runLoopDidTick(_ loop: CoreRunLoop)
}

/// Simple GCD timer run loop usable before CADisplayLink is wired in the app target.
public final class CoreRunLoop: @unchecked Sendable {
    public weak var driver: CoreRunLoopDriving?
    public private(set) var isRunning = false

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var timer: DispatchSourceTimer?
    /// GBA ~59.7275 Hz; use 60 for the stub host.
    public var framesPerSecond: Double = 60 {
        didSet { rescheduleIfNeeded() }
    }

    public init(label: String = "RetroPlay.CoreRunLoop") {
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
        self.queue.setSpecific(key: queueKey, value: 1)
    }

    /// Run `body` on the emu queue (re-entrant if already there). Required for save/load vs runFrame.
    public func sync(_ body: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            body()
        } else {
            queue.sync(execute: body)
        }
    }

    public func syncThrows<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    public func start() {
        stop()
        isRunning = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1.0 / max(framesPerSecond, 1)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            self.driver?.runLoopDidTick(self)
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    private func rescheduleIfNeeded() {
        guard isRunning, let timer else { return }
        let interval = 1.0 / max(framesPerSecond, 1)
        timer.schedule(deadline: .now(), repeating: interval)
    }

    deinit { stop() }
}

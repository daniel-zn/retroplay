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
    private var timer: DispatchSourceTimer?
    /// GBA ~59.7275 Hz; use 60 for the stub host.
    public var framesPerSecond: Double = 60

    public init(label: String = "RetroPlay.CoreRunLoop") {
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
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

    deinit { stop() }
}

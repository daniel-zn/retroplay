// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The one thread every native core runs on.
///
/// PPSSPP and mupen64plus keep process-global state, and the N64 GL context is bound
/// per thread, so all load / run / save / teardown work is serialized here. Only one
/// session is ever resident: loading a game tears down whatever is still loaded first,
/// even if the previous game's `stop()` has not been queued yet.
///
/// Frame pacing uses absolute deadlines on the monotonic clock (not a repeating
/// timer with leeway), so frames stay evenly spaced and a late frame is caught up
/// rather than lost.
final class EmulationThread: @unchecked Sendable {
    static let shared = EmulationThread()

    private let condition = NSCondition()
    private var pending: [@Sendable () -> Void] = []
    private var thread: Thread?

    /// Thread-confined: only read or written by work items running on this thread.
    private var active: EmulationSession?
    /// Thread-confined: the one session whose native core is loaded (running or not).
    private var resident: EmulationSession?

    private init() {}

    /// Queue `work` on the emulation thread and return immediately.
    func enqueue(_ work: @escaping @Sendable () -> Void) {
        condition.lock()
        pending.append(work)
        if thread == nil {
            let thread = Thread { [unowned self] in self.main() }
            thread.name = "RetroPlay.Emulation"
            thread.qualityOfService = .userInteractive
            // Cores recurse deeply (PPSSPP IR, GLideN64); the 512 KB default is not enough.
            thread.stackSize = 16 << 20
            self.thread = thread
            thread.start()
        }
        condition.signal()
        condition.unlock()
    }

    /// Run `work` on the emulation thread and await its result.
    func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Emulation thread only.
    func activate(_ session: EmulationSession?) {
        active = session
    }

    /// Emulation thread only.
    func isActive(_ session: EmulationSession) -> Bool {
        active === session
    }

    /// Emulation thread only. Tears down whatever session is loaded. Call before loading
    /// a new driver: PPSSPP and mupen64plus cannot hold two games at once.
    func evictResident() {
        guard let old = resident else { return }
        if active === old { active = nil }
        resident = nil
        old.tearDown()
    }

    /// Emulation thread only. `session` becomes the loaded one (any other is torn down).
    func makeResident(_ session: EmulationSession) {
        if resident !== session { evictResident() }
        resident = session
    }

    /// Emulation thread only. False once another load evicted `session`.
    func isResident(_ session: EmulationSession) -> Bool {
        resident === session
    }

    /// Emulation thread only. Tears `session` down if it is still the loaded one;
    /// a session already evicted by a newer load is left alone.
    func release(_ session: EmulationSession) {
        guard resident === session else { return }
        if active === session { active = nil }
        resident = nil
        session.tearDown()
    }

    private func main() {
        while true {
            autoreleasepool {
                runOnce()
            }
        }
    }

    private func runOnce() {
        condition.lock()
        while pending.isEmpty {
            guard let session = active, session.isRunnable else {
                condition.wait()
                continue
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= session.nextDeadline {
                break
            }
            let wait = Double(session.nextDeadline - now) / 1_000_000_000
            _ = condition.wait(until: Date(timeIntervalSinceNow: wait))
        }
        let work = pending
        pending.removeAll(keepingCapacity: true)
        condition.unlock()

        for item in work {
            item()
        }

        if let session = active, session.isRunnable,
           DispatchTime.now().uptimeNanoseconds >= session.nextDeadline {
            session.tick()
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class PlaySessionLifecycleTests: XCTestCase {
    func testSessionTokenBumpInvalidatesPreviousBoot() {
        let initial = PlaySessionToken(rawValue: 4)
        let bumped = PlaySessionLifecycle.bump(initial)
        XCTAssertEqual(bumped.rawValue, 5)
        XCTAssertTrue(bumped.isCurrent(live: bumped))
        XCTAssertFalse(initial.isCurrent(live: bumped))
    }

    func testBackgroundOnlyPausesRunningPlayback() {
        let transition = PlaySceneLifecycle.transition(
            to: .background,
            userPlayback: .running,
            pausedForBackground: false
        )
        XCTAssertTrue(transition.shouldPauseCore)
        XCTAssertFalse(transition.shouldResumeCore)
        XCTAssertTrue(transition.markPausedForBackground)
    }

    func testInactiveDoesNotAutoPause() {
        XCTAssertEqual(
            PlaySceneLifecycle.transition(
                to: .inactive,
                userPlayback: .running,
                pausedForBackground: false
            ),
            .noop
        )
    }

    func testForegroundResumesOnlyAfterBackgroundPause() {
        let transition = PlaySceneLifecycle.transition(
            to: .active,
            userPlayback: .running,
            pausedForBackground: true
        )
        XCTAssertFalse(transition.shouldPauseCore)
        XCTAssertTrue(transition.shouldResumeCore)
        XCTAssertTrue(transition.clearPausedForBackground)
    }

    func testForegroundDoesNotResumeUserPausedPlayback() {
        let transition = PlaySceneLifecycle.transition(
            to: .active,
            userPlayback: .paused,
            pausedForBackground: true
        )
        XCTAssertFalse(transition.shouldResumeCore)
        XCTAssertTrue(transition.clearPausedForBackground)
    }

    func testPlaybackResumePolicyHonorsBackgroundPause() {
        XCTAssertFalse(
            PlaybackResumePolicy.shouldResumeAfterOperation(
                userPaused: false,
                pausedForBackground: true
            )
        )
        XCTAssertTrue(
            PlaybackResumePolicy.shouldResumeAfterOperation(
                userPaused: false,
                pausedForBackground: false
            )
        )
        XCTAssertFalse(
            PlaybackResumePolicy.shouldResumeAfterOperation(
                userPaused: true,
                pausedForBackground: false
            )
        )
    }

    @MainActor
    func testBatterySaveReloadWaitsForSaveIdle() async {
        var busy = true
        var polls = 0
        let ready = await BatterySaveReload.waitForSaveIdle(
            isSaveBusy: {
                polls += 1
                if polls >= 2 { busy = false }
                return busy
            },
            sleep: { _ in }
        )
        XCTAssertTrue(ready)
        XCTAssertGreaterThanOrEqual(polls, 2)
    }

    @MainActor
    func testBatterySaveReloadTimesOutWhenSaveStaysBusy() async {
        let ready = await BatterySaveReload.waitForSaveIdle(
            isSaveBusy: { true },
            sleep: { _ in }
        )
        XCTAssertFalse(ready)
    }

    func testLeavePlaySkipsAutoSaveWhenSaveStillBusy() {
        XCTAssertFalse(LeavePlayPolicy.shouldAutoSaveAfterWaiting(saveStillBusy: true))
        XCTAssertTrue(LeavePlayPolicy.shouldAutoSaveAfterWaiting(saveStillBusy: false))
    }

    func testBatterySaveReloadTimeoutNoticeIsActionable() {
        XCTAssertTrue(BatterySaveReload.saveIdleTimeoutNotice.contains("Stop and relaunch"))
    }
}

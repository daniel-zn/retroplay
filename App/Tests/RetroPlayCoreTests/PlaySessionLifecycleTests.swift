// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import RetroPlayCore

final class PlaySessionLifecycleTests: XCTestCase {
    func testSessionTokenBumpInvalidatesPreviousBoot() {
        let initial = PlaySessionToken(rawValue: 4)
        let bumped = initial.bumped()
        XCTAssertEqual(bumped.rawValue, 5)
        XCTAssertTrue(bumped.isCurrent(live: bumped))
        XCTAssertFalse(initial.isCurrent(live: bumped))
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

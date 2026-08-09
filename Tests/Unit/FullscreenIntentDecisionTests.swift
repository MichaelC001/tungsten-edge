import CoreGraphics
import XCTest

final class FullscreenIntentDecisionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testGreenButtonAcceptsExactHitAndIgnoresNonModifierFlags() {
        let snapshot = makeSnapshot()
        let request = FullscreenIntentDecision.greenButtonRequest(
            location: CGPoint(x: 120, y: 110),
            flags: [.maskAlphaShift, .maskNonCoalesced],
            snapshot: snapshot
        )
        XCTAssertEqual(request?.source, .greenButton)
        XCTAssertEqual(request?.focusedWindowID, snapshot.focusedWindowID)
    }

    func testGreenButtonRejectsModifiersCapabilityAndContextMismatches() {
        let point = CGPoint(x: 120, y: 110)
        for modifier: CGEventFlags in [
            .maskControl, .maskCommand, .maskAlternate, .maskShift,
            .maskSecondaryFn, .maskHelp, .maskNumericPad
        ] {
            XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
                location: point, flags: modifier, snapshot: makeSnapshot()
            ))
        }
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: CGPoint(x: 200, y: 200), flags: [], snapshot: makeSnapshot()
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: [], snapshot: makeSnapshot(buttonEnabled: false)
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: [], snapshot: makeSnapshot(isFullscreen: true)
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: [], snapshot: makeSnapshot(panelScreen: nil)
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point,
            flags: [],
            snapshot: makeSnapshot(panelScreen: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: [], snapshot: nil
        ))
    }

    func testShortcutAcceptsExactControlCommandAndCapsLock() {
        let request = FullscreenIntentDecision.shortcutRequest(
            keyCode: FullscreenIntentDecision.ansiFKeyCode,
            flags: [.maskControl, .maskCommand, .maskAlphaShift, .maskNonCoalesced],
            isRepeat: false,
            snapshot: makeSnapshot()
        )
        XCTAssertEqual(request?.source, .keyboardShortcut)
    }

    func testShortcutRejectsExtraModifiersRepeatWrongKeyAndMissingCapability() {
        for flags: CGEventFlags in [
            [.maskControl, .maskCommand, .maskAlternate],
            [.maskControl, .maskCommand, .maskShift],
            [.maskControl, .maskCommand, .maskSecondaryFn],
            [.maskControl, .maskCommand, .maskHelp],
            [.maskControl, .maskCommand, .maskNumericPad],
            [.maskCommand]
        ] {
            XCTAssertNil(FullscreenIntentDecision.shortcutRequest(
                keyCode: FullscreenIntentDecision.ansiFKeyCode,
                flags: flags,
                isRepeat: false,
                snapshot: makeSnapshot()
            ))
        }
        XCTAssertNil(FullscreenIntentDecision.shortcutRequest(
            keyCode: FullscreenIntentDecision.ansiFKeyCode,
            flags: [.maskControl, .maskCommand],
            isRepeat: true,
            snapshot: makeSnapshot()
        ))
        XCTAssertNil(FullscreenIntentDecision.shortcutRequest(
            keyCode: 4,
            flags: [.maskControl, .maskCommand],
            isRepeat: false,
            snapshot: makeSnapshot()
        ))
        XCTAssertNil(FullscreenIntentDecision.shortcutRequest(
            keyCode: FullscreenIntentDecision.ansiFKeyCode,
            flags: [.maskControl, .maskCommand],
            isRepeat: false,
            snapshot: makeSnapshot(buttonEnabled: false)
        ))
    }

    func testSettingAndEnvironmentMustBothEnableMonitor() {
        XCTAssertTrue(FullscreenIntentDecision.isEnabled(settingEnabled: true, environment: [:]))
        XCTAssertFalse(FullscreenIntentDecision.isEnabled(
            settingEnabled: true,
            environment: ["DOCK_FULLSCREEN_INTENT": "0"]
        ))
        XCTAssertFalse(FullscreenIntentDecision.isEnabled(settingEnabled: false, environment: [:]))
    }

    func testStaleAXRefreshAndForegroundPIDSwitchCannotReplaceCache() {
        XCTAssertTrue(FullscreenIntentCacheDecision.shouldApplyRefresh(
            started: true,
            expectedObservation: 4,
            currentObservation: 4,
            expectedCache: 7,
            currentCache: 7,
            requestedPID: 123,
            activePID: 123
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.shouldApplyRefresh(
            started: true,
            expectedObservation: 4,
            currentObservation: 5,
            expectedCache: 7,
            currentCache: 7,
            requestedPID: 123,
            activePID: 123
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.shouldApplyRefresh(
            started: true,
            expectedObservation: 4,
            currentObservation: 4,
            expectedCache: 7,
            currentCache: 8,
            requestedPID: 123,
            activePID: 123
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.shouldApplyRefresh(
            started: true,
            expectedObservation: 4,
            currentObservation: 4,
            expectedCache: 7,
            currentCache: 7,
            requestedPID: 123,
            activePID: 124
        ))
    }

    func testRequestMustMatchCurrentPIDWindowScreenAndCacheGeneration() {
        let snapshot = makeSnapshot()
        let request = FullscreenIntentDecision.shortcutRequest(
            keyCode: FullscreenIntentDecision.ansiFKeyCode,
            flags: [.maskControl, .maskCommand],
            isRepeat: false,
            snapshot: snapshot
        )!
        XCTAssertTrue(FullscreenIntentCacheDecision.isCurrentRequest(
            request,
            snapshot: snapshot,
            activePID: snapshot.pid,
            started: true
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.isCurrentRequest(
            request,
            snapshot: makeSnapshot(generation: 10),
            activePID: snapshot.pid,
            started: true
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.isCurrentRequest(
            request,
            snapshot: makeSnapshot(focusedWindowID: 999),
            activePID: snapshot.pid,
            started: true
        ))
        XCTAssertFalse(FullscreenIntentCacheDecision.isCurrentRequest(
            request,
            snapshot: snapshot,
            activePID: 124,
            started: true
        ))
    }

    func testRefreshCoalescerCollapsesBurstIntoOneTrailingRefresh() {
        var coalescer = FullscreenIntentRefreshCoalescer()
        let first = coalescer.request()!
        XCTAssertNil(coalescer.request())
        XCTAssertNil(coalescer.request())
        XCTAssertTrue(coalescer.needsTrailingRefresh)

        guard case let .start(second) = coalescer.complete(token: first) else {
            return XCTFail("burst must schedule exactly one trailing refresh")
        }
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(coalescer.needsTrailingRefresh)
        XCTAssertEqual(coalescer.complete(token: first), .ignored)
        XCTAssertEqual(coalescer.complete(token: second), .idle)
        XCTAssertNil(coalescer.activeToken)
    }

    func testRefreshCoalescerResetInvalidatesOldCompletion() {
        var coalescer = FullscreenIntentRefreshCoalescer()
        let old = coalescer.request()!
        coalescer.reset()
        let current = coalescer.request()!

        XCTAssertEqual(coalescer.complete(token: old), .ignored)
        XCTAssertEqual(coalescer.activeToken, current)
        XCTAssertEqual(coalescer.complete(token: current), .idle)
    }

    func testTapRecoveryFusesOnFourthDisableWithinWindow() {
        var policy = FullscreenEventTapRecoveryPolicy()
        XCTAssertTrue(policy.recordDisable(at: 0))
        XCTAssertTrue(policy.recordDisable(at: 1))
        XCTAssertTrue(policy.recordDisable(at: 2))
        XCTAssertFalse(policy.recordDisable(at: 3))
        XCTAssertTrue(policy.isFused)
        XCTAssertFalse(policy.recordDisable(at: 64))
    }

    func testTapRecoveryDropsOldEpisodesOutsideWindow() {
        var policy = FullscreenEventTapRecoveryPolicy()
        XCTAssertTrue(policy.recordDisable(at: 0))
        XCTAssertTrue(policy.recordDisable(at: 1))
        XCTAssertTrue(policy.recordDisable(at: 61))
        XCTAssertTrue(policy.recordDisable(at: 62))
        XCTAssertFalse(policy.isFused)
    }

    func testLateHandoffCannotBeginAfterCancellation() {
        let gate = FullscreenIntentHandoffGate()
        XCTAssertTrue(gate.cancelIfPending())
        XCTAssertFalse(gate.beginExecution())
        XCTAssertEqual(gate.currentState, .cancelled)
    }

    func testExecutingHandoffCompletesAndCannotBeCancelled() {
        let gate = FullscreenIntentHandoffGate()
        XCTAssertTrue(gate.beginExecution())
        XCTAssertFalse(gate.cancelIfPending())
        gate.complete()
        XCTAssertEqual(gate.currentState, .completed)
    }

    // MARK: - Control+←/→ 空间切换实验

    /// 这一条是整个实验最容易翻车的地方：**物理方向键天生带 Fn + 小键盘 + nonCoalesced**，
    /// 用户一个附加键都没按也是如此。照 `FullscreenIntentDecision.normalizedModifiers`
    /// 那套比对会永远匹配不上，得到一个「什么都不触发」的假阴性，而它极容易被读成
    /// 「548ms 提前量不够，这条路走不通」。
    func testPhysicalArrowIntrinsicFlagsDoNotBlockTheMatch() {
        let physicalControlLeft: CGEventFlags = [
            .maskControl, .maskSecondaryFn, .maskNumericPad, .maskNonCoalesced
        ]
        XCTAssertTrue(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
            keyCode: FullscreenSpaceSwitchDecision.leftArrowKeyCode,
            flags: physicalControlLeft,
            isRepeat: false
        ))
        XCTAssertTrue(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
            keyCode: FullscreenSpaceSwitchDecision.rightArrowKeyCode,
            flags: physicalControlLeft,
            isRepeat: false
        ))
    }

    func testSpaceSwitchArrowRejectsEveryOtherShape() {
        let intrinsic: CGEventFlags = [.maskSecondaryFn, .maskNumericPad, .maskNonCoalesced]
        // 没按 Control
        XCTAssertFalse(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
            keyCode: FullscreenSpaceSwitchDecision.leftArrowKeyCode,
            flags: intrinsic,
            isRepeat: false
        ))
        // 多带了别的修饰键
        for extra: CGEventFlags in [.maskCommand, .maskAlternate, .maskShift, .maskHelp] {
            XCTAssertFalse(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
                keyCode: FullscreenSpaceSwitchDecision.leftArrowKeyCode,
                flags: intrinsic.union([.maskControl]).union(extra),
                isRepeat: false
            ), "\(extra) 不该放行")
        }
        // 上下方向键不是切空间
        for keyCode in [CGKeyCode(125), CGKeyCode(126)] {
            XCTAssertFalse(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
                keyCode: keyCode,
                flags: intrinsic.union([.maskControl]),
                isRepeat: false
            ))
        }
        // 长按重复不再触发
        XCTAssertFalse(FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
            keyCode: FullscreenSpaceSwitchDecision.rightArrowKeyCode,
            flags: intrinsic.union([.maskControl]),
            isRepeat: true
        ))
    }

    func testSpaceSwitchExperimentIsOffUnlessExplicitlyEnabled() {
        XCTAssertFalse(FullscreenSpaceSwitchDecision.isExperimentEnabled(environment: [:]))
        XCTAssertFalse(FullscreenSpaceSwitchDecision.isExperimentEnabled(
            environment: ["DOCK_SPACE_INTENT_EXPERIMENT": "0"]
        ))
        XCTAssertTrue(FullscreenSpaceSwitchDecision.isExperimentEnabled(
            environment: ["DOCK_SPACE_INTENT_EXPERIMENT": "1"]
        ))
    }

    private func makeSnapshot(
        generation: UInt64 = 9,
        focusedWindowID: CGWindowID = 456,
        buttonEnabled: Bool = true,
        isFullscreen: Bool = false,
        panelScreen: CGRect? = CGRect(x: 0, y: 0, width: 1512, height: 982)
    ) -> FullscreenIntentSnapshot {
        FullscreenIntentSnapshot(
            generation: generation,
            pid: 123,
            focusedWindowID: focusedWindowID,
            buttonFrame: CGRect(x: 100, y: 100, width: 40, height: 20),
            windowFrame: CGRect(x: 80, y: 80, width: 900, height: 700),
            screenCGFrame: screen,
            panelScreenCGFrame: panelScreen,
            isFullscreen: isFullscreen,
            buttonEnabled: buttonEnabled
        )
    }

}

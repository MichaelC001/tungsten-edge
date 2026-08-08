import CoreGraphics
import XCTest

final class FullscreenIntentDecisionTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testGreenButtonAcceptsExactHitWithoutWindowUnderPointerData() {
        let snapshot = makeSnapshot()
        let request = FullscreenIntentDecision.greenButtonRequest(
            location: CGPoint(x: 120, y: 110),
            flags: [],
            snapshot: snapshot
        )
        XCTAssertEqual(request?.source, .greenButton)
        XCTAssertEqual(request?.focusedWindowID, snapshot.focusedWindowID)
    }

    func testGreenButtonRejectsModifiersCapabilityAndContextMismatches() {
        let point = CGPoint(x: 120, y: 110)
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: .maskAlternate, snapshot: makeSnapshot()
        ))
        XCTAssertNil(FullscreenIntentDecision.greenButtonRequest(
            location: point, flags: .maskShift, snapshot: makeSnapshot()
        ))
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
            flags: [.maskControl, .maskCommand, .maskAlphaShift],
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

    func testChangedNonFullscreenRequiresSameWindowAndChangedFrame() {
        let initial = CGRect(x: 10, y: 10, width: 800, height: 600)
        let changed = CGRect(x: 10, y: 10, width: 900, height: 700)
        XCTAssertTrue(FullscreenIntentStabilityDecision.isChangedNonFullscreen(
            initialWindowFrame: initial,
            currentWindowID: 7,
            expectedWindowID: 7,
            currentWindowFrame: changed,
            isFullscreen: false
        ))
        XCTAssertFalse(FullscreenIntentStabilityDecision.isChangedNonFullscreen(
            initialWindowFrame: initial,
            currentWindowID: 8,
            expectedWindowID: 7,
            currentWindowFrame: changed,
            isFullscreen: false
        ))
        XCTAssertFalse(FullscreenIntentStabilityDecision.isChangedNonFullscreen(
            initialWindowFrame: initial,
            currentWindowID: 7,
            expectedWindowID: 7,
            currentWindowFrame: initial,
            isFullscreen: false
        ))
        XCTAssertFalse(FullscreenIntentStabilityDecision.isChangedNonFullscreen(
            initialWindowFrame: initial,
            currentWindowID: 7,
            expectedWindowID: 7,
            currentWindowFrame: changed,
            isFullscreen: true
        ))
    }

    func testStableNonFullscreenRequiresTwoMatchingSamples() {
        let initial = CGRect(x: 10, y: 10, width: 800, height: 600)
        let changed = CGRect(x: 10, y: 10, width: 900, height: 700)
        let first = makeWindowState(frame: changed)
        XCTAssertTrue(FullscreenIntentStabilityDecision.shouldCancel(
            initialWindowFrame: initial,
            expectedWindowID: 456,
            first: first,
            second: first
        ))
        XCTAssertFalse(FullscreenIntentStabilityDecision.shouldCancel(
            initialWindowFrame: initial,
            expectedWindowID: 456,
            first: first,
            second: makeWindowState(frame: CGRect(x: 10, y: 10, width: 901, height: 700))
        ))
        XCTAssertFalse(FullscreenIntentStabilityDecision.shouldCancel(
            initialWindowFrame: initial,
            expectedWindowID: 456,
            first: first,
            second: makeWindowState(frame: changed, isFullscreen: true)
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

    private func makeWindowState(
        frame: CGRect,
        isFullscreen: Bool = false
    ) -> FullscreenIntentWindowState {
        FullscreenIntentWindowState(
            pid: 123,
            focusedWindowID: 456,
            windowFrame: frame,
            screenCGFrame: screen,
            isFullscreen: isFullscreen
        )
    }
}

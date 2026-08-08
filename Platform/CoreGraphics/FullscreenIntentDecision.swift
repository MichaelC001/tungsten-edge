import CoreGraphics
import Foundation
import os.lock

enum FullscreenIntentSource: String, Equatable {
    case greenButton
    case keyboardShortcut
}

struct FullscreenIntentSnapshot: Equatable {
    let generation: UInt64
    let pid: pid_t
    let focusedWindowID: CGWindowID
    let buttonFrame: CGRect
    let windowFrame: CGRect
    let screenCGFrame: CGRect
    let panelScreenCGFrame: CGRect?
    let isFullscreen: Bool
    let buttonEnabled: Bool
}

struct FullscreenIntentRequest: Equatable {
    let source: FullscreenIntentSource
    let cacheGeneration: UInt64
    let pid: pid_t
    let focusedWindowID: CGWindowID
    let windowFrame: CGRect
    let screenCGFrame: CGRect
}

struct FullscreenIntentWindowState: Equatable {
    let pid: pid_t
    let focusedWindowID: CGWindowID
    let windowFrame: CGRect
    let screenCGFrame: CGRect
    let isFullscreen: Bool
}

enum FullscreenIntentDecision {
    static let ansiFKeyCode = CGKeyCode(3)

    private static let shortcutModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskHelp,
        .maskNumericPad
    ]

    static func greenButtonRequest(
        location: CGPoint,
        flags: CGEventFlags,
        snapshot: FullscreenIntentSnapshot?
    ) -> FullscreenIntentRequest? {
        guard let snapshot,
              snapshot.buttonEnabled,
              !snapshot.isFullscreen,
              snapshot.panelScreenCGFrame == snapshot.screenCGFrame,
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              snapshot.buttonFrame.contains(location) else {
            return nil
        }
        return request(source: .greenButton, snapshot: snapshot)
    }

    static func shortcutRequest(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isRepeat: Bool,
        snapshot: FullscreenIntentSnapshot?
    ) -> FullscreenIntentRequest? {
        guard let snapshot,
              snapshot.buttonEnabled,
              !snapshot.isFullscreen,
              snapshot.panelScreenCGFrame == snapshot.screenCGFrame,
              !isRepeat,
              keyCode == ansiFKeyCode,
              flags.intersection(shortcutModifiers) == [.maskCommand, .maskControl] else {
            return nil
        }
        return request(source: .keyboardShortcut, snapshot: snapshot)
    }

    static func isEnabled(
        settingEnabled: Bool,
        environment: [String: String]
    ) -> Bool {
        settingEnabled && environment["DOCK_FULLSCREEN_INTENT"] != "0"
    }

    private static func request(
        source: FullscreenIntentSource,
        snapshot: FullscreenIntentSnapshot
    ) -> FullscreenIntentRequest {
        FullscreenIntentRequest(
            source: source,
            cacheGeneration: snapshot.generation,
            pid: snapshot.pid,
            focusedWindowID: snapshot.focusedWindowID,
            windowFrame: snapshot.windowFrame,
            screenCGFrame: snapshot.screenCGFrame
        )
    }
}

enum FullscreenIntentCacheDecision {
    static func shouldApplyRefresh(
        started: Bool,
        expectedObservation: UInt64,
        currentObservation: UInt64,
        expectedCache: UInt64,
        currentCache: UInt64,
        requestedPID: pid_t,
        activePID: pid_t?
    ) -> Bool {
        started
            && expectedObservation == currentObservation
            && expectedCache == currentCache
            && requestedPID == activePID
    }

    static func isCurrentRequest(
        _ request: FullscreenIntentRequest,
        snapshot: FullscreenIntentSnapshot?,
        activePID: pid_t?,
        started: Bool
    ) -> Bool {
        guard started, activePID == request.pid, let snapshot else { return false }
        return snapshot.generation == request.cacheGeneration
            && snapshot.pid == request.pid
            && snapshot.focusedWindowID == request.focusedWindowID
            && snapshot.screenCGFrame == request.screenCGFrame
    }
}

enum FullscreenIntentStabilityDecision {
    static func isChangedNonFullscreen(
        initialWindowFrame: CGRect,
        currentWindowID: CGWindowID,
        expectedWindowID: CGWindowID,
        currentWindowFrame: CGRect,
        isFullscreen: Bool
    ) -> Bool {
        currentWindowID == expectedWindowID
            && !isFullscreen
            && currentWindowFrame != initialWindowFrame
    }

    static func shouldCancel(
        initialWindowFrame: CGRect,
        expectedWindowID: CGWindowID,
        first: FullscreenIntentWindowState,
        second: FullscreenIntentWindowState
    ) -> Bool {
        isChangedNonFullscreen(
            initialWindowFrame: initialWindowFrame,
            currentWindowID: first.focusedWindowID,
            expectedWindowID: expectedWindowID,
            currentWindowFrame: first.windowFrame,
            isFullscreen: first.isFullscreen
        )
            && isChangedNonFullscreen(
                initialWindowFrame: initialWindowFrame,
                currentWindowID: second.focusedWindowID,
                expectedWindowID: expectedWindowID,
                currentWindowFrame: second.windowFrame,
                isFullscreen: second.isFullscreen
            )
            && first.pid == second.pid
            && first.screenCGFrame == second.screenCGFrame
            && first.windowFrame == second.windowFrame
    }
}

struct FullscreenEventTapRecoveryPolicy: Equatable {
    static let window: TimeInterval = 60
    static let maximumReenables = 3

    private(set) var disableTimes: [TimeInterval] = []
    private(set) var isFused = false

    mutating func recordDisable(at now: TimeInterval) -> Bool {
        guard !isFused else { return false }
        disableTimes.removeAll { now - $0 > Self.window }
        guard disableTimes.count < Self.maximumReenables else {
            isFused = true
            return false
        }
        disableTimes.append(now)
        return true
    }
}

final class FullscreenIntentHandoffGate {
    enum State: Equatable {
        case pending
        case executing
        case completed
        case cancelled
    }

    private var lock = os_unfair_lock_s()
    private var state: State = .pending

    func beginExecution() -> Bool {
        withLock {
            guard state == .pending else { return false }
            state = .executing
            return true
        }
    }

    func complete() {
        withLock {
            guard state == .executing else { return }
            state = .completed
        }
    }

    @discardableResult
    func cancelIfPending() -> Bool {
        withLock {
            guard state == .pending else { return false }
            state = .cancelled
            return true
        }
    }

    var currentState: State { withLock { state } }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}

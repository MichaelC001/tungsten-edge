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
    let screenCGFrame: CGRect
}

enum FullscreenIntentDecision {
    static let ansiFKeyCode = CGKeyCode(3)

    private static let intentModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskHelp,
        .maskNumericPad
    ]

    static func normalizedModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(intentModifiers)
    }

    static func greenButtonRequest(
        location: CGPoint,
        flags: CGEventFlags,
        snapshot: FullscreenIntentSnapshot?
    ) -> FullscreenIntentRequest? {
        guard let snapshot,
              snapshot.buttonEnabled,
              !snapshot.isFullscreen,
              snapshot.panelScreenCGFrame == snapshot.screenCGFrame,
              normalizedModifiers(flags).isEmpty,
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
              normalizedModifiers(flags) == [.maskCommand, .maskControl] else {
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
            screenCGFrame: snapshot.screenCGFrame
        )
    }
}

struct FullscreenIntentRefreshCoalescer: Equatable {
    enum Completion: Equatable {
        case ignored
        case idle
        case start(UInt64)
    }

    private(set) var activeToken: UInt64?
    private(set) var needsTrailingRefresh = false
    private var nextToken: UInt64 = 0

    mutating func request() -> UInt64? {
        guard activeToken == nil else {
            needsTrailingRefresh = true
            return nil
        }
        return begin()
    }

    mutating func complete(token: UInt64) -> Completion {
        guard activeToken == token else { return .ignored }
        if needsTrailingRefresh {
            needsTrailingRefresh = false
            let trailingToken = begin()
            return .start(trailingToken)
        }
        activeToken = nil
        return .idle
    }

    mutating func reset() {
        activeToken = nil
        needsTrailingRefresh = false
    }

    private mutating func begin() -> UInt64 {
        nextToken &+= 1
        activeToken = nextToken
        return nextToken
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

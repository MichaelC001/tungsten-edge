import AppKit
import ApplicationServices
import Foundation
import OSLog
import os.lock

private final class FullscreenIntentAtomicState {
    private var lock = os_unfair_lock_s()
    private var snapshot: FullscreenIntentSnapshot?
    private var tapEnabled = false

    func currentSnapshot() -> FullscreenIntentSnapshot? {
        withLock { tapEnabled ? snapshot : nil }
    }

    func replaceSnapshot(_ value: FullscreenIntentSnapshot?) {
        withLock { snapshot = value }
    }

    func updatePanelScreen(_ frame: CGRect?) {
        withLock {
            guard let current = snapshot else { return }
            snapshot = FullscreenIntentSnapshot(
                generation: current.generation,
                pid: current.pid,
                focusedWindowID: current.focusedWindowID,
                buttonFrame: current.buttonFrame,
                windowFrame: current.windowFrame,
                screenCGFrame: current.screenCGFrame,
                panelScreenCGFrame: frame,
                isFullscreen: current.isFullscreen,
                buttonEnabled: current.buttonEnabled
            )
        }
    }

    func setTapEnabled(_ enabled: Bool) {
        withLock { tapEnabled = enabled }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}

private final class FullscreenIntentEventBridge {
    private static let handoffTimeout: DispatchTimeInterval = .milliseconds(150)

    private let state: FullscreenIntentAtomicState
    private let logger: Logger
    private let onIntent: (FullscreenIntentRequest) -> Void
    private let onSpaceSwitchIntent: () -> Void
    private let spaceSwitchExperimentEnabled: Bool

    init(
        state: FullscreenIntentAtomicState,
        logger: Logger,
        spaceSwitchExperimentEnabled: Bool,
        onIntent: @escaping (FullscreenIntentRequest) -> Void,
        onSpaceSwitchIntent: @escaping () -> Void
    ) {
        self.state = state
        self.logger = logger
        self.spaceSwitchExperimentEnabled = spaceSwitchExperimentEnabled
        self.onIntent = onIntent
        self.onSpaceSwitchIntent = onSpaceSwitchIntent
    }

    func handle(type: CGEventType, event: CGEvent) {
        let request: FullscreenIntentRequest?
        switch type {
        case .leftMouseDown:
            request = FullscreenIntentDecision.greenButtonRequest(
                location: event.location,
                flags: event.flags,
                snapshot: state.currentSnapshot()
            )
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // 空间切换实验先判：它不依赖 AX 快照（切空间时前台窗口能不能全屏无关紧要），
            // 而 shortcutRequest 没有快照就直接返回 nil。
            if spaceSwitchExperimentEnabled,
               FullscreenSpaceSwitchDecision.isSpaceSwitchArrow(
                   keyCode: keyCode,
                   flags: event.flags,
                   isRepeat: isRepeat
               ) {
                performHandoff(label: "spaceSwitch", pid: nil) { [weak self] in
                    self?.onSpaceSwitchIntent()
                }
                return
            }
            request = FullscreenIntentDecision.shortcutRequest(
                keyCode: keyCode,
                flags: event.flags,
                isRepeat: isRepeat,
                snapshot: state.currentSnapshot()
            )
        default:
            request = nil
        }
        guard let request else { return }
        performHandoff(label: request.source.rawValue, pid: request.pid) { [weak self] in
            self?.onIntent(request)
        }
    }

    /// 命中后唯一的主线程交接：有上限地**同步**等待，`orderOut` 完成才放行原始输入 ——
    /// 这是唯一被实测证明有效的时序条件，不能改成 `main.async`。超时后迟到的 block 由
    /// `FullscreenIntentHandoffGate` 变成 no-op，输入原样放行（退化成今天的闪烁）。
    private func performHandoff(label: String, pid: pid_t?, _ body: @escaping () -> Void) {
        let gate = FullscreenIntentHandoffGate()
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            guard gate.beginExecution() else {
                completion.signal()
                return
            }
            body()
            gate.complete()
            completion.signal()
        }

        if completion.wait(timeout: .now() + Self.handoffTimeout) == .timedOut {
            let cancelled = gate.cancelIfPending()
            logger.error(
                "handoff-timeout source=\(label, privacy: .public) pid=\(pid ?? -1, privacy: .public) cancelled=\(cancelled, privacy: .public)"
            )
        }
    }
}

private final class FullscreenIntentEventTapThread {
    private let logger: Logger
    private let bridge: FullscreenIntentEventBridge
    private let atomicState: FullscreenIntentAtomicState
    private var lifecycleLock = os_unfair_lock_s()
    private var recoveryLock = os_unfair_lock_s()
    private var recoveryPolicy = FullscreenEventTapRecoveryPolicy()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var stopping = false
    private let finished = DispatchSemaphore(value: 0)

    init(
        logger: Logger,
        bridge: FullscreenIntentEventBridge,
        atomicState: FullscreenIntentAtomicState
    ) {
        self.logger = logger
        self.bridge = bridge
        self.atomicState = atomicState
    }

    func start() {
        withLifecycleLock {
            guard thread == nil else { return }
            stopping = false
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "com.caye.macosdockcc.fullscreen-intent-tap"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            thread.start()
        }
    }

    func stop() {
        atomicState.setTapEnabled(false)
        let loop: CFRunLoop? = withLifecycleLock {
            stopping = true
            return runLoop
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { return }
                if let tap = self.withLifecycleLock({ self.tap }) {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFMachPortInvalidate(tap)
                }
                CFRunLoopStop(loop)
            }
            CFRunLoopWakeUp(loop)
            _ = finished.wait(timeout: .now() + 1)
        }
        withLifecycleLock {
            thread = nil
            runLoop = nil
            tap = nil
        }
    }

    private func run() {
        autoreleasepool {
            let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                logger.error("event-tap-create-failed")
                finished.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let currentLoop = CFRunLoopGetCurrent()
            let shouldStop = withLifecycleLock {
                self.tap = tap
                runLoop = currentLoop
                return stopping
            }
            guard !shouldStop else {
                CFMachPortInvalidate(tap)
                finished.signal()
                return
            }
            CFRunLoopAddSource(currentLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            atomicState.setTapEnabled(true)
            CFRunLoopRun()
            atomicState.setTapEnabled(false)
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            finished.signal()
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<FullscreenIntentEventTapThread>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            owner.handleDisabled(type: type)
        } else {
            owner.bridge.handle(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleDisabled(type: CGEventType) {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldReenable: Bool = withRecoveryLock {
            recoveryPolicy.recordDisable(at: now)
        }
        guard shouldReenable, let tap = withLifecycleLock({ self.tap }) else {
            atomicState.setTapEnabled(false)
            logger.fault("event-tap-fused type=\(type.rawValue, privacy: .public)")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        atomicState.setTapEnabled(true)
        logger.error("event-tap-reenabled type=\(type.rawValue, privacy: .public)")
    }

    private func withLifecycleLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lifecycleLock)
        defer { os_unfair_lock_unlock(&lifecycleLock) }
        return body()
    }

    private func withRecoveryLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&recoveryLock)
        defer { os_unfair_lock_unlock(&recoveryLock) }
        return body()
    }
}

@MainActor
final class FullscreenIntentMonitor {
    enum ContextChange {
        case activeApplication(pid_t?)
        case focusedWindow
        case windowDestroyed(CGWindowID?)
    }

    private struct AXReadResult {
        let element: AXUIElement
        let pid: pid_t
        let windowID: CGWindowID
        let buttonFrame: CGRect
        let windowFrame: CGRect
        let screenCGFrame: CGRect
        let isFullscreen: Bool
        let buttonEnabled: Bool
    }

    private let logger = Logger(
        subsystem: "com.caye.macosdockcc.v2",
        category: "FullscreenIntent"
    )
    private let atomicState = FullscreenIntentAtomicState()
    private let onIntent: (FullscreenIntentRequest) -> Void
    private let onSpaceSwitchIntent: () -> Void
    private let onContextChange: (ContextChange) -> Void
    private let spaceSwitchExperimentEnabled: Bool
    private lazy var bridge = FullscreenIntentEventBridge(
        state: atomicState,
        logger: logger,
        spaceSwitchExperimentEnabled: spaceSwitchExperimentEnabled,
        onIntent: { [weak self] request in self?.accept(request) },
        onSpaceSwitchIntent: { [weak self] in
            guard let self, self.started else { return }
            self.onSpaceSwitchIntent()
        }
    )
    private lazy var tapThread = FullscreenIntentEventTapThread(
        logger: logger,
        bridge: bridge,
        atomicState: atomicState
    )

    private var workspaceActivationObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var appElement: AXUIElement?
    private var focusedElement: AXUIElement?
    private var focusedWindowID: CGWindowID?
    private var activePID: pid_t?
    private var panelScreenCGFrame: CGRect?
    private var observationGeneration: UInt64 = 0
    private var cacheGeneration: UInt64 = 0
    private var refreshCoalescer = FullscreenIntentRefreshCoalescer()
    private var started = false

    init(
        spaceSwitchExperimentEnabled: Bool = FullscreenSpaceSwitchDecision.isExperimentEnabled(
            environment: ProcessInfo.processInfo.environment
        ),
        onIntent: @escaping (FullscreenIntentRequest) -> Void,
        onSpaceSwitchIntent: @escaping () -> Void,
        onContextChange: @escaping (ContextChange) -> Void
    ) {
        self.spaceSwitchExperimentEnabled = spaceSwitchExperimentEnabled
        self.onIntent = onIntent
        self.onSpaceSwitchIntent = onSpaceSwitchIntent
        self.onContextChange = onContextChange
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            Task { @MainActor [weak self] in self?.activate(pid: pid) }
        }
        tapThread.start()
        let initialPID = NSWorkspace.shared.runningApplications.first(where: { $0.isActive })?.processIdentifier
        activate(pid: initialPID)
    }

    func stop() {
        guard started else { return }
        started = false
        observationGeneration &+= 1
        cacheGeneration &+= 1
        refreshCoalescer.reset()
        atomicState.replaceSnapshot(nil)
        if let observer = workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceActivationObserver = nil
        }
        stopAXObservation()
        tapThread.stop()
    }

    func updatePanelScreen(_ frame: CGRect?) {
        panelScreenCGFrame = frame
        atomicState.updatePanelScreen(frame)
    }

    private func accept(_ request: FullscreenIntentRequest) {
        guard FullscreenIntentCacheDecision.isCurrentRequest(
            request,
            snapshot: atomicState.currentSnapshot(),
            activePID: activePID,
            started: started
        ) else {
            return
        }
        onIntent(request)
    }

    private func activate(pid: pid_t?) {
        guard activePID != pid || axObserver == nil else { return }
        activePID = pid
        observationGeneration &+= 1
        cacheGeneration &+= 1
        atomicState.replaceSnapshot(nil)
        stopAXObservation()
        onContextChange(.activeApplication(pid))
        guard let pid else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &observer) == .success,
              let observer else {
            return
        }
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.1)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        appElement = app
        refreshCache()
    }

    private func stopAXObservation() {
        if let observer = axObserver {
            unregisterFocusedElement(observer: observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        appElement = nil
        focusedElement = nil
        focusedWindowID = nil
    }

    private func refreshCache() {
        guard let pid = activePID else { return }
        guard let token = refreshCoalescer.request() else { return }
        startCacheRefresh(token: token, pid: pid)
    }

    private func startCacheRefresh(token: UInt64, pid: pid_t) {
        let expectedCache = cacheGeneration
        let expectedObservation = observationGeneration
        let screens = Self.screenFrames()
        Task.detached(priority: .userInitiated) {
            let result = Self.readAXState(pid: pid, screenFrames: screens)
            await MainActor.run { [weak self] in
                self?.finishCacheRefresh(
                    token: token,
                    result: result,
                    pid: pid,
                    expectedCache: expectedCache,
                    expectedObservation: expectedObservation
                )
            }
        }
    }

    private func finishCacheRefresh(
        token: UInt64,
        result: AXReadResult?,
        pid: pid_t,
        expectedCache: UInt64,
        expectedObservation: UInt64
    ) {
        let completion = refreshCoalescer.complete(token: token)
        guard completion != .ignored else { return }

        if FullscreenIntentCacheDecision.shouldApplyRefresh(
            started: started,
            expectedObservation: expectedObservation,
            currentObservation: observationGeneration,
            expectedCache: expectedCache,
            currentCache: cacheGeneration,
            requestedPID: pid,
            activePID: activePID
        ) {
            if let result {
                registerFocusedElement(result.element, windowID: result.windowID)
                atomicState.replaceSnapshot(FullscreenIntentSnapshot(
                    generation: expectedCache,
                    pid: result.pid,
                    focusedWindowID: result.windowID,
                    buttonFrame: result.buttonFrame,
                    windowFrame: result.windowFrame,
                    screenCGFrame: result.screenCGFrame,
                    panelScreenCGFrame: panelScreenCGFrame,
                    isFullscreen: result.isFullscreen,
                    buttonEnabled: result.buttonEnabled
                ))
            } else {
                atomicState.replaceSnapshot(nil)
                unregisterFocusedElement(observer: axObserver)
            }
        }

        if case let .start(nextToken) = completion {
            guard started, let nextPID = activePID else {
                refreshCoalescer.reset()
                return
            }
            startCacheRefresh(token: nextToken, pid: nextPID)
        }
    }

    private func invalidateCache() {
        cacheGeneration &+= 1
        atomicState.replaceSnapshot(nil)
    }

    private func registerFocusedElement(_ element: AXUIElement, windowID: CGWindowID) {
        guard let observer = axObserver else { return }
        if focusedWindowID == windowID { return }
        unregisterFocusedElement(observer: observer)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXWindowResizedNotification as CFString, refcon)
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        focusedElement = element
        focusedWindowID = windowID
    }

    private func unregisterFocusedElement(observer: AXObserver?) {
        guard let observer, let element = focusedElement else {
            focusedElement = nil
            focusedWindowID = nil
            return
        }
        AXObserverRemoveNotification(observer, element, kAXWindowMovedNotification as CFString)
        AXObserverRemoveNotification(observer, element, kAXWindowResizedNotification as CFString)
        AXObserverRemoveNotification(observer, element, kAXUIElementDestroyedNotification as CFString)
        focusedElement = nil
        focusedWindowID = nil
    }

    private func handleAXNotification(_ notification: CFString) {
        let name = notification as String
        if name == (kAXFocusedWindowChangedNotification as String) {
            invalidateCache()
            onContextChange(.focusedWindow)
            refreshCache()
        } else if name == (kAXWindowCreatedNotification as String) {
            // 原生全屏转场本身会创建临时 AX 元素；这不是焦点离开原窗口的证据。
            invalidateCache()
            refreshCache()
        } else if name == (kAXWindowMovedNotification as String)
            || name == (kAXWindowResizedNotification as String) {
            invalidateCache()
            refreshCache()
        } else if name == (kAXUIElementDestroyedNotification as String) {
            let windowID = focusedWindowID
            invalidateCache()
            onContextChange(.windowDestroyed(windowID))
            unregisterFocusedElement(observer: axObserver)
            refreshCache()
        }
    }

    private static let axCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let monitor = Unmanaged<FullscreenIntentMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // The observer source is installed on CFRunLoopGetMain(), so invalidate during the
        // notification turn instead of adding a second main-queue hop.
        MainActor.assumeIsolated {
            monitor.handleAXNotification(notification)
        }
    }

    nonisolated private static func readAXState(
        pid: pid_t,
        screenFrames: [CGRect]
    ) -> AXReadResult? {
        let reader = AXWindowReader()
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.1)
        guard let focused = reader.elementAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: app,
            maxAttempts: 1
        ) else { return nil }
        _ = AXUIElementSetMessagingTimeout(focused, 0.1)
        guard reader.stringAttribute(kAXRoleAttribute as CFString, from: focused, maxAttempts: 1) == kAXWindowRole,
              let windowID = reader.cgWindowID(for: focused, maxAttempts: 1),
              let windowFrame = reader.frame(of: focused, maxAttempts: 1),
              let screenFrame = screenFrames.max(by: {
                  $0.intersection(windowFrame).area < $1.intersection(windowFrame).area
              }),
              screenFrame.intersects(windowFrame),
              let button = reader.elementAttribute(
                  "AXFullScreenButton" as CFString,
                  from: focused,
                  maxAttempts: 1
              ) else { return nil }
        _ = AXUIElementSetMessagingTimeout(button, 0.1)
        guard let buttonFrame = reader.frame(of: button, maxAttempts: 1) else { return nil }
        let isAXFullscreen = reader.boolAttribute(
            "AXFullScreen" as CFString,
            from: focused,
            maxAttempts: 1
        ) ?? false
        let isFullscreen = FullscreenWindowClassifier.isFullscreen(
            role: kAXWindowRole,
            isAXFullscreen: isAXFullscreen,
            windowFrame: windowFrame,
            screenCGFrame: screenFrame
        )
        return AXReadResult(
            element: focused,
            pid: pid,
            windowID: windowID,
            buttonFrame: buttonFrame,
            windowFrame: windowFrame,
            screenCGFrame: screenFrame,
            isFullscreen: isFullscreen,
            buttonEnabled: reader.boolAttribute(
                kAXEnabledAttribute as CFString,
                from: button,
                maxAttempts: 1
            ) ?? false
        )
    }

    private static func screenFrames() -> [CGRect] {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return NSScreen.screens.map { screen in
            let frame = screen.frame
            return CGRect(
                x: frame.minX,
                y: primaryHeight - frame.maxY,
                width: frame.width,
                height: frame.height
            )
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

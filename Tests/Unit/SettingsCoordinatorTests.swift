import XCTest

@MainActor
final class SettingsCoordinatorTests: XCTestCase {
    func testLaunchStateStartsFromCacheThenRefreshesFromService() async {
        let store = makeStore(launchAtLogin: true)
        let launch = LaunchServiceStub(state: .off)
        let coordinator = makeCoordinator(store: store, launch: launch)

        XCTAssertEqual(coordinator.launchAtLoginState, .on)
        let firstRefreshAccepted = await coordinator.refreshLaunchAtLoginState()
        XCTAssertTrue(firstRefreshAccepted)
        XCTAssertEqual(coordinator.launchAtLoginState, .off)

        launch.state = .requiresApproval
        let secondRefreshAccepted = await coordinator.refreshLaunchAtLoginState()
        XCTAssertTrue(secondRefreshAccepted)
        XCTAssertEqual(coordinator.launchAtLoginState, .requiresApproval)
    }

    func testLaunchFailureDoesNotChangeStoredMirror() {
        let store = makeStore(launchAtLogin: false)
        let launch = LaunchServiceStub(state: .off)
        launch.setError = TestError.failed
        let coordinator = makeCoordinator(store: store, launch: launch)

        guard case .failure = coordinator.setLaunchAtLogin(true) else {
            return XCTFail("expected failure")
        }
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(coordinator.launchAtLoginState, .off)
    }

    func testLaunchSuccessUpdatesMirrorAndPublishedState() {
        let store = makeStore(launchAtLogin: false)
        let launch = LaunchServiceStub(state: .off)
        launch.stateAfterSet = .on
        let coordinator = makeCoordinator(store: store, launch: launch)

        guard case .success = coordinator.setLaunchAtLogin(true) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertEqual(coordinator.launchAtLoginState, .on)
    }

    func testNativeApplyReadsLivePreviousAndPublishesReadback() async {
        let store = makeStore(nativeDelay: AppSettingsStore.neverHideDelay)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.4),
            NativeDockAutohideState(enabled: true, delay: 0.7),
        ])
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = await coordinator.applyNativeDock(target: 1.0)

        XCTAssertEqual(native.appliedDelays, [1.0])
        XCTAssertEqual(outcome.resolvedDelay, 0.7)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.7)
    }

    func testNativeApplyFallsBackToMirrorWhenBothReadsFail() async {
        let store = makeStore(nativeDelay: 0.3)
        let native = NativeDockServiceStub(states: [nil, nil])
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = await coordinator.applyNativeDock(target: 1.0)

        XCTAssertEqual(outcome.resolvedDelay, 1.0)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 1.0)
    }

    func testNativeFailureAndUnreadableReadbackKeepsLivePrevious() async {
        let store = makeStore(nativeDelay: 0.2)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.6),
            nil,
        ])
        native.applyError = TestError.failed
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = await coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.6)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.6)
    }

    func testNativeFailureStillUsesReadablePartialResult() async {
        let store = makeStore(nativeDelay: 0.2)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.6),
            NativeDockAutohideState(enabled: true, delay: 0.8),
        ])
        native.applyError = TestError.failed
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = await coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.8)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.8)
    }

    func testSandboxUnavailableDoesNotWriteOrChangeMirror() async {
        let store = makeStore(nativeDelay: 0.5)
        let native = NativeDockServiceStub(isAvailable: false)
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = await coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.5)
        XCTAssertTrue(native.appliedDelays.isEmpty)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.5)
    }

    func testOlderLaunchRefreshCannotOverwriteNewerResult() async {
        let reader = ControlledLaunchStateReader()
        let launch = ControlledLaunchService(reader: reader)
        let coordinator = SettingsCoordinator(
            store: makeStore(),
            launchAtLoginService: launch,
            nativeDockPreferencesService: NativeDockServiceStub(),
            updateChecker: UpdateCheckerStub(),
            subscriptionSubmitter: SubscriptionSubmitterStub()
        )

        let older = Task { await coordinator.refreshLaunchAtLoginState() }
        await reader.waitForReadCount(1)
        let newer = Task { await coordinator.refreshLaunchAtLoginState() }
        await reader.waitForReadCount(2)

        await reader.resume(id: 1, state: .on)
        let newerAccepted = await newer.value
        XCTAssertTrue(newerAccepted)
        await reader.resume(id: 0, state: .off)
        let olderAccepted = await older.value
        XCTAssertFalse(olderAccepted)
        XCTAssertEqual(coordinator.launchAtLoginState, .on)
    }

    func testPrewarmReadCannotOverwriteNativeDockWrite() async {
        let reader = ControlledNativeDockStateReader()
        let native = ControlledNativeDockService(reader: reader)
        let store = makeStore(nativeDelay: 0.1)
        let coordinator = SettingsCoordinator(
            store: store,
            launchAtLoginService: LaunchServiceStub(state: .off),
            nativeDockPreferencesService: native,
            updateChecker: UpdateCheckerStub(),
            subscriptionSubmitter: SubscriptionSubmitterStub()
        )

        let prewarm = Task { await coordinator.reconcileNativeDockMirror() }
        await reader.waitForReadCount(1)
        let write = Task { await coordinator.applyNativeDock(target: 0.9) }
        await reader.waitForReadCount(2)

        await reader.resume(id: 0, state: NativeDockAutohideState(enabled: true, delay: 0.2))
        let prewarmAccepted = await prewarm.value
        XCTAssertFalse(prewarmAccepted)
        await reader.resume(id: 1, state: NativeDockAutohideState(enabled: true, delay: 0.3))
        await reader.waitForReadCount(3)
        await reader.resume(id: 2, state: NativeDockAutohideState(enabled: true, delay: 0.9))

        let outcome = await write.value
        XCTAssertEqual(native.appliedDelays, [0.9])
        XCTAssertEqual(outcome.resolvedDelay, 0.9)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.9)
    }

    /// 在飞守卫是**共享**的：菜单和设置窗口各有一个「检查更新」入口，
    /// 各守各的会同时发两次请求。
    func testUpdateCheckGuardIsSharedAcrossBothEntryPoints() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.beginUpdateCheck())
        XCTAssertFalse(coordinator.beginUpdateCheck())
        XCTAssertFalse(coordinator.updateCheckState.presentation.isEnabled)

        coordinator.finishUpdateCheck()
        XCTAssertTrue(coordinator.updateCheckState.presentation.isEnabled)
        XCTAssertTrue(coordinator.beginUpdateCheck())
    }

    func testUpdateCheckFailureMapsToSharedFailureCopy() async {
        let updates = UpdateCheckerStub()
        updates.error = TestError.failed
        let coordinator = makeCoordinator(updates: updates)

        let content = await coordinator.performUpdateCheck()
        XCTAssertEqual(content, UpdateCheckAlertContent.failure)
        XCTAssertTrue(content.isWarning)
        XCTAssertEqual(updates.checkCount, 1)
    }

    private func makeCoordinator(
        store: AppSettingsStore? = nil,
        launch: LaunchServiceStub? = nil,
        native: NativeDockServiceStub? = nil,
        updates: UpdateCheckerStub? = nil,
        subscriptions: SubscriptionSubmitterStub? = nil
    ) -> SettingsCoordinator {
        SettingsCoordinator(
            store: store ?? makeStore(),
            launchAtLoginService: launch ?? LaunchServiceStub(state: .off),
            nativeDockPreferencesService: native ?? NativeDockServiceStub(),
            updateChecker: updates ?? UpdateCheckerStub(),
            subscriptionSubmitter: subscriptions ?? SubscriptionSubmitterStub()
        )
    }

    private func makeStore(
        launchAtLogin: Bool = false,
        nativeDelay: Double = AppSettingsStore.defaultNativeDockAutoHideDelay
    ) -> AppSettingsStore {
        let suite = "SettingsCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(launchAtLogin, forKey: "com.tungsten.edge.launchAtLogin")
        defaults.set(nativeDelay, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        return AppSettingsStore(defaults: defaults)
    }
}

@MainActor
private final class LaunchServiceStub: LaunchAtLoginServicing {
    var state: LaunchAtLoginState
    var stateAfterSet: LaunchAtLoginState?
    var setError: Error?

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func currentState() async -> LaunchAtLoginState { state }

    func setEnabled(_ enabled: Bool) throws {
        if let setError { throw setError }
        state = stateAfterSet ?? (enabled ? .on : .off)
    }

    func openSystemSettings() {}
}

@MainActor
private final class NativeDockServiceStub: NativeDockPreferencesServicing {
    let isAvailable: Bool
    var states: [NativeDockAutohideState?]
    var applyError: Error?
    var appliedDelays: [Double] = []

    init(isAvailable: Bool = true, states: [NativeDockAutohideState?] = []) {
        self.isAvailable = isAvailable
        self.states = states
    }

    func apply(delay: Double) throws {
        appliedDelays.append(delay)
        if let applyError { throw applyError }
    }

    func currentAutohideState() async -> NativeDockAutohideState? {
        states.isEmpty ? nil : states.removeFirst()
    }

    func openSystemSettings() -> Bool { true }
}

private actor ControlledLaunchStateReader {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<LaunchAtLoginState, Never>] = [:]

    func read() async -> LaunchAtLoginState {
        let id = nextID
        nextID += 1
        return await withCheckedContinuation { continuations[id] = $0 }
    }

    func waitForReadCount(_ count: Int) async {
        while nextID < count { await Task.yield() }
    }

    func resume(id: Int, state: LaunchAtLoginState) {
        continuations.removeValue(forKey: id)?.resume(returning: state)
    }
}

@MainActor
private final class ControlledLaunchService: LaunchAtLoginServicing {
    private let reader: ControlledLaunchStateReader

    init(reader: ControlledLaunchStateReader) {
        self.reader = reader
    }

    func currentState() async -> LaunchAtLoginState { await reader.read() }
    func setEnabled(_ enabled: Bool) throws {}
    func openSystemSettings() {}
}

private actor ControlledNativeDockStateReader {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<NativeDockAutohideState?, Never>] = [:]

    func read() async -> NativeDockAutohideState? {
        let id = nextID
        nextID += 1
        return await withCheckedContinuation { continuations[id] = $0 }
    }

    func waitForReadCount(_ count: Int) async {
        while nextID < count { await Task.yield() }
    }

    func resume(id: Int, state: NativeDockAutohideState?) {
        continuations.removeValue(forKey: id)?.resume(returning: state)
    }
}

@MainActor
private final class ControlledNativeDockService: NativeDockPreferencesServicing {
    let isAvailable = true
    private let reader: ControlledNativeDockStateReader
    private(set) var appliedDelays: [Double] = []

    init(reader: ControlledNativeDockStateReader) {
        self.reader = reader
    }

    func apply(delay: Double) throws { appliedDelays.append(delay) }
    func currentAutohideState() async -> NativeDockAutohideState? { await reader.read() }
    func openSystemSettings() -> Bool { true }
}

private final class SubscriptionSubmitterStub: SubscriptionSubmitting, @unchecked Sendable {
    var outcome: SubscriptionOutcome = .created
    var error: Error?
    private(set) var submitCount = 0
    private(set) var lastEmail: String?
    private(set) var lastFirstLaunchDate: Date?

    func submit(email: String, firstLaunchDate: Date?) async throws -> SubscriptionOutcome {
        submitCount += 1
        lastEmail = email
        lastFirstLaunchDate = firstLaunchDate
        if let error { throw error }
        return outcome
    }
}

private final class UpdateCheckerStub: UpdateChecking, @unchecked Sendable {
    var outcome: UpdateCheckOutcome?
    var error: Error?
    private(set) var checkCount = 0

    func check(currentVersion: String) async throws -> UpdateCheckOutcome {
        checkCount += 1
        if let error { throw error }
        return outcome ?? .upToDate(currentVersion: currentVersion, latestVersion: currentVersion)
    }
}

private enum TestError: Error {
    case failed
}

import ApplicationServices
import Combine
import XCTest

final class AXWindowReaderResultTests: XCTestCase {
    func testSuccessPreservesOriginalWindowArray() {
        let snapshot = AXWindowSnapshot(
            pid: 42,
            cgWindowID: 123,
            title: "test",
            bounds: nil,
            role: nil,
            subrole: nil,
            isMinimized: false,
            isFocusedWindow: false,
            element: AXUIElementCreateApplication(42)
        )

        let windows = AXWindowReadResult.success([snapshot]).windowsOrEmpty

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].pid, snapshot.pid)
        XCTAssertEqual(windows[0].cgWindowID, snapshot.cgWindowID)
    }

    func testUnreadStillMapsToEmptyArrayAndKeepsError() {
        let result = AXWindowReadResult.unread(.cannotComplete)

        XCTAssertTrue(result.windowsOrEmpty.isEmpty)
        guard case .unread(let error) = result else {
            return XCTFail("expected unread")
        }
        XCTAssertEqual(error, .cannotComplete)
    }
}

final class ActionExecutionSwitchesTests: XCTestCase {
    func testFastHandleMetadataPreservesSnapshotTarget() {
        let bounds = CGRect(x: 10, y: 20, width: 900, height: 700)
        let rawHandle = AXWindowHandle(
            pid: 42,
            title: nil,
            bounds: nil,
            element: AXUIElementCreateApplication(42)
        )
        let handle = AccessibilityWindowActionExecutor.fastHandle(
            from: rawHandle,
            target: .init(pid: 42, title: "Project Window", bounds: bounds)
        )

        XCTAssertEqual(handle.pid, 42)
        XCTAssertEqual(handle.title, "Project Window")
        XCTAssertEqual(handle.bounds, bounds)
    }

    func testTargetMetadataSelectsOneWindowWhileMissingMetadataStaysAmbiguous() {
        let targetBounds = CGRect(x: 10, y: 20, width: 900, height: 700)
        let candidates = [
            AXWindowMatchPolicy.Candidate(
                title: "Project Window",
                bounds: CGRect(x: 1000, y: 20, width: 900, height: 700)
            ),
            AXWindowMatchPolicy.Candidate(title: "Project Window", bounds: targetBounds),
        ]

        XCTAssertEqual(AXWindowMatchPolicy.uniqueBestMatchIndex(
            targetTitle: "Project Window",
            targetBounds: targetBounds,
            candidates: candidates
        ), 1)
        XCTAssertNil(AXWindowMatchPolicy.uniqueBestMatchIndex(
            targetTitle: nil,
            targetBounds: nil,
            candidates: candidates
        ))
    }

    func testDefaultsUseFastHandleAndDisableDiagnosticsAndMinimizeFallback() {
        let switches = ActionExecutionSwitches(environment: [:])

        XCTAssertTrue(switches.fastWindowHandleEnabled)
        XCTAssertFalse(switches.chipProbeEnabled)
        XCTAssertFalse(switches.minimizeAppFallbackEnabled)
    }

    func testCompatibilityKillSwitchesAreDirectional() {
        let switches = ActionExecutionSwitches(environment: [
            "DOCK_FAST_WINDOW_HANDLE": "0",
            "DOCK_CHIP_PROBE": "1",
            "DOCK_MINIMIZE_APP_FALLBACK": "1"
        ])

        XCTAssertFalse(switches.fastWindowHandleEnabled)
        XCTAssertTrue(switches.chipProbeEnabled)
        XCTAssertTrue(switches.minimizeAppFallbackEnabled)
    }

    func testFastHandleHitSkipsFallback() {
        var fastCalls = 0
        var fallbackCalls = 0
        let result: String? = WindowHandleCapturePlan.capture(
            fastEnabled: true,
            cgWindowID: 7,
            justUnhid: false,
            fast: { _ in fastCalls += 1; return "fast" },
            fallback: { fallbackCalls += 1; return "fallback" }
        )

        XCTAssertEqual(result, "fast")
        XCTAssertEqual(fastCalls, 1)
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testFastHandleMissFallsBackExactlyOnce() {
        var fastCalls = 0
        var fallbackCalls = 0
        let result: String? = WindowHandleCapturePlan.capture(
            fastEnabled: true,
            cgWindowID: 7,
            justUnhid: false,
            fast: { _ in fastCalls += 1; return nil },
            fallback: { fallbackCalls += 1; return "fallback" }
        )

        XCTAssertEqual(result, "fallback")
        XCTAssertEqual(fastCalls, 1)
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testMinimizeCaptureFailureDoesNotUseAppFallbackByDefault() {
        XCTAssertFalse(WindowHandleCapturePlan.usesAppFallbackAfterCaptureFailure(
            requestKind: .minimizeWindow,
            isFinderWindow: false,
            minimizeAppFallbackEnabled: false
        ))
        XCTAssertTrue(WindowHandleCapturePlan.usesAppFallbackAfterCaptureFailure(
            requestKind: .minimizeWindow,
            isFinderWindow: false,
            minimizeAppFallbackEnabled: true
        ))
        XCTAssertTrue(WindowHandleCapturePlan.usesAppFallbackAfterCaptureFailure(
            requestKind: .activateWindow,
            isFinderWindow: false,
            minimizeAppFallbackEnabled: false
        ))
    }
}

@MainActor
final class AppTrackerReadSemanticsTests: XCTestCase {
    private let pid: pid_t = 4242
    private let cgWindowID: CGWindowID = 77

    func testUnreadRoundPreservesSeatAbsenceAndShadowState() throws {
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppTrackerUnreadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let inventoryLog = WindowInventoryAnomalyLog(configuration: .init(
            enabled: true,
            directoryURL: logDirectory,
            maxFileSize: 1_000_000,
            archiveCount: 1
        ))
        let tracker = AppTracker(inventoryLog: inventoryLog, eventAXAsyncEnabled: true)
        let absence = Date(timeIntervalSince1970: 10)
        let episode = UUID()
        tracker.installFixtureForTesting(makeApp(
            isMinimized: true,
            absentSince: absence,
            episodeID: episode,
            shadowIDs: [88, 89]
        ))

        let changed = tracker.reconcileFixtureForTesting(
            pid: pid,
            cgSnapshot: emptyCGSnapshot(),
            now: Date(timeIntervalSince1970: 100),
            eligible: [],
            readOutcome: .unread(errorCode: AXError.cannotComplete.rawValue)
        )

        XCTAssertFalse(changed)
        let app = tracker.fixtureAppForTesting(pid: pid)
        XCTAssertEqual(app?.windowOrder, [cgWindowID])
        XCTAssertEqual(app?.shadowTabCgIDs, [88, 89])
        XCTAssertEqual(app?.windowsByID[cgWindowID]?.minAbsentSince, absence)
        XCTAssertEqual(app?.windowsByID[cgWindowID]?.absenceEpisodeID, episode)

        inventoryLog.flush()
        let text = try String(contentsOf: inventoryLog.currentFileURL, encoding: .utf8)
        let record = try XCTUnwrap(text.split(separator: "\n").first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any]
        )
        XCTAssertEqual(json["event"] as? String, "reconcileUnread")
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["readMode"] as? String, "timed")
        XCTAssertEqual(payload["usedPreloadedAX"] as? Bool, true)
        XCTAssertEqual(payload["errorCode"] as? Int, Int(AXError.cannotComplete.rawValue))
    }

    func testSuccessfulEmptyRoundKeepsShadowPoolWhenCGStillHasWindows() {
        let tracker = AppTracker(eventAXAsyncEnabled: true)
        tracker.installFixtureForTesting(makeApp(shadowIDs: [88, 89]))
        let cgSnapshot = AppTrackerCGWindowSnapshot(
            allWindowIDs: [cgWindowID, 88, 89],
            onScreenWindowIDs: [],
            windowIDsByPID: [pid: [cgWindowID, 88, 89]],
            alphaByWindowID: [:]
        )

        _ = tracker.reconcileFixtureForTesting(
            pid: pid,
            cgSnapshot: cgSnapshot,
            now: Date(),
            eligible: [],
            readOutcome: .success(count: 0)
        )

        XCTAssertEqual(tracker.fixtureAppForTesting(pid: pid)?.shadowTabCgIDs, [88, 89])
    }

    func testEventBurstRunsOneLeadingAndExactlyOneTrailingRead() async {
        let reader = ControlledAppTrackerReader()
        let tracker = AppTracker(
            reader: reader,
            processProvider: FixedAppTrackerProcessProvider(pid: pid),
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleEventReadForTesting(pid: pid, source: .windowCreated)
        tracker.scheduleEventReadForTesting(pid: pid, source: .focusChanged)
        tracker.scheduleEventReadForTesting(pid: pid, source: .titleChanged)

        await waitUntil { reader.readCount == 1 }
        reader.releaseOne()
        await waitUntil { reader.readCount == 2 }
        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pid) }

        XCTAssertEqual(reader.readCount, 2)
    }

    func testFrontmostPollUsesTimedBackgroundReader() async {
        let reader = ControlledAppTrackerReader(result: .success([]))
        let tracker = AppTracker(
            reader: reader,
            processProvider: FixedAppTrackerProcessProvider(pid: pid),
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleFrontmostPollForTesting(pid: pid)

        await waitUntil { reader.readCount == 1 }
        XCTAssertEqual(reader.untimedReadCount, 0)
        XCTAssertTrue(tracker.hasPendingEventReadForTesting(pid: pid))

        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pid) }
    }

    func testMinimizeMutationRejectsOlderAsyncRead() async {
        let reader = ControlledAppTrackerReader(result: .success([]))
        let tracker = AppTracker(
            reader: reader,
            processProvider: FixedAppTrackerProcessProvider(pid: pid),
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleEventReadForTesting(pid: pid, source: .focusChanged)
        await waitUntil { reader.readCount == 1 }
        tracker.minimizeForTesting(pid: pid, cgWindowID: cgWindowID)
        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pid) }

        XCTAssertEqual(tracker.fixtureAppForTesting(pid: pid)?.windowsByID[cgWindowID]?.isMinimized, true)
    }

    func testDestroyMutationRejectsOlderAsyncRead() async {
        let reader = ControlledAppTrackerReader(result: .success([]))
        let tracker = AppTracker(
            reader: reader,
            processProvider: FixedAppTrackerProcessProvider(pid: pid),
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleEventReadForTesting(pid: pid, source: .titleChanged)
        await waitUntil { reader.readCount == 1 }
        tracker.destroyForTesting(pid: pid, cgWindowID: cgWindowID)
        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pid) }

        XCTAssertNotNil(tracker.fixtureAppForTesting(pid: pid)?.windowsByID[cgWindowID])
    }

    func testPIDReuseRejectsOlderAsyncRead() async {
        let reader = ControlledAppTrackerReader(result: .success([]))
        let processProvider = MutableAppTrackerProcessProvider(pid: pid)
        let tracker = AppTracker(
            reader: reader,
            processProvider: processProvider,
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleEventReadForTesting(pid: pid, source: .windowCreated)
        await waitUntil { reader.readCount == 1 }
        processProvider.advanceGeneration()
        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pid) }

        XCTAssertNotNil(tracker.fixtureAppForTesting(pid: pid)?.windowsByID[cgWindowID])
    }

    func testAsyncKillSwitchUsesSynchronousReader() {
        let reader = ControlledAppTrackerReader(result: .unread(.cannotComplete), blocksTimedReads: false)
        let tracker = AppTracker(
            reader: reader,
            processProvider: FixedAppTrackerProcessProvider(pid: pid),
            cgSnapshotProvider: { self.emptyCGSnapshot() },
            onScreenWindowIDsProvider: { [] },
            eventAXAsyncEnabled: false
        )
        tracker.installFixtureForTesting(makeApp())

        tracker.scheduleEventReadForTesting(pid: pid, source: .focusChanged)

        XCTAssertEqual(reader.untimedReadCount, 1)
        XCTAssertFalse(tracker.hasPendingEventReadForTesting(pid: pid))
    }

    func testEquivalentSnapshotRebuildPublishesOnlyOnce() {
        let tracker = AppTracker(eventAXAsyncEnabled: true)
        tracker.installFixtureForTesting(makeApp())
        var publicationCount = 0
        let subscription = tracker.$snapshot.dropFirst().sink { _ in publicationCount += 1 }

        tracker.rebuildSnapshotForTesting()
        tracker.rebuildSnapshotForTesting()

        XCTAssertEqual(publicationCount, 1)
        withExtendedLifetime(subscription) {}
    }

    private func makeApp(
        isMinimized: Bool = false,
        absentSince: Date? = nil,
        episodeID: UUID? = nil,
        shadowIDs: Set<CGWindowID> = []
    ) -> AppEntry {
        let seat = WindowEntry(
            cgWindowID: cgWindowID,
            token: "tabgrp-\(pid)-s1",
            title: "Window",
            bounds: CGRect(x: 10, y: 20, width: 500, height: 400),
            isMinimized: isMinimized,
            isFocused: !isMinimized,
            absentSince: absentSince,
            minAbsentSince: absentSince,
            absenceEpisodeID: episodeID,
            everSeenVisible: true
        )
        return AppEntry(
            pid: pid,
            bundleIdentifier: "com.example.fixture",
            appName: "Fixture",
            activationPolicy: .regular,
            executablePath: "/Applications/Fixture.app",
            windowsByID: [cgWindowID: seat],
            windowOrder: [cgWindowID],
            isHidden: false,
            shadowTabCgIDs: shadowIDs
        )
    }

    private nonisolated func emptyCGSnapshot() -> AppTrackerCGWindowSnapshot {
        AppTrackerCGWindowSnapshot(
            allWindowIDs: [],
            onScreenWindowIDs: [],
            windowIDsByPID: [:],
            alphaByWindowID: [:]
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition(), DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private final class ControlledAppTrackerReader: AppTrackerWindowReading, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var count = 0
    private var untimedCount = 0
    private let result: AXWindowReadResult
    private let untimedResult: AXWindowReadResult
    private let blocksTimedReads: Bool

    init(
        result: AXWindowReadResult = .unread(.cannotComplete),
        untimedResult: AXWindowReadResult = .unread(.cannotComplete),
        blocksTimedReads: Bool = true
    ) {
        self.result = result
        self.untimedResult = untimedResult
        self.blocksTimedReads = blocksTimedReads
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var untimedReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return untimedCount
    }

    func releaseOne() {
        semaphore.signal()
    }

    func windows(forPID pid: pid_t) -> [AXWindowSnapshot] { [] }

    func windowReadResult(forPID pid: pid_t) -> AXWindowReadResult {
        lock.lock()
        untimedCount += 1
        lock.unlock()
        return untimedResult
    }

    func inventoryWindows(forPID pid: pid_t, messagingTimeout: TimeInterval) -> AXWindowReadResult {
        lock.lock()
        count += 1
        lock.unlock()
        if blocksTimedReads { semaphore.wait() }
        return result
    }
}

private final class MutableAppTrackerProcessProvider: AppTrackerProcessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let pid: pid_t
    private var generation: Int64 = 1

    init(pid: pid_t) {
        self.pid = pid
    }

    func advanceGeneration() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    func isAlive(pid: pid_t) -> Bool { pid == self.pid }

    func identity(pid: pid_t, bundleID: String?) -> ScanAdmissionDecision.ProcessIdentity {
        lock.lock()
        let current = generation
        lock.unlock()
        return ScanAdmissionDecision.ProcessIdentity(
            pid: pid,
            startTimeSec: current,
            startTimeUsec: 0,
            bundleID: bundleID
        )
    }
}

private struct FixedAppTrackerProcessProvider: AppTrackerProcessProviding {
    let pid: pid_t

    func isAlive(pid: pid_t) -> Bool { pid == self.pid }

    func identity(pid: pid_t, bundleID: String?) -> ScanAdmissionDecision.ProcessIdentity {
        ScanAdmissionDecision.ProcessIdentity(
            pid: pid,
            startTimeSec: 1,
            startTimeUsec: 2,
            bundleID: bundleID
        )
    }
}

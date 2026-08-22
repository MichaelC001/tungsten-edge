import ApplicationServices
import CoreGraphics
import XCTest

/// 周期对账批量后台读（schedulePeriodicBatchRead / completePeriodicBatch）的行为锁：
/// 每 pid 恰读一次并落地、在途事件读抑制批读、代际变更丢弃落地、`.unread` 不动座位状态。
@MainActor
final class AppTrackerPeriodicBatchTests: XCTestCase {
    private let pidA: pid_t = 4242
    private let pidB: pid_t = 4343
    private let cgWindowA: CGWindowID = 77
    private let cgWindowB: CGWindowID = 88

    func testBatchReadsEachTrackedPidOnceAndAppliesResult() async {
        let reader = PeriodicBatchReader(resultsByPID: [
            pidA: .success([makeSnapshot(pid: pidA, cgWindowID: cgWindowA, title: "Renamed A")]),
            pidB: .success([makeSnapshot(pid: pidB, cgWindowID: cgWindowB, title: "Renamed B")]),
        ])
        let tracker = AppTracker(
            reader: reader,
            processProvider: BatchFixedProcessProvider(),
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp(pid: pidA, cgWindowID: cgWindowA))
        tracker.installFixtureForTesting(makeApp(pid: pidB, cgWindowID: cgWindowB))

        tracker.runPeriodicBatchForTesting(cgSnapshot: cgSnapshot())
        XCTAssertTrue(tracker.hasPendingEventReadForTesting(pid: pidA))
        XCTAssertTrue(tracker.hasPendingEventReadForTesting(pid: pidB))

        await waitUntil {
            !tracker.hasPendingEventReadForTesting(pid: self.pidA)
                && !tracker.hasPendingEventReadForTesting(pid: self.pidB)
        }

        XCTAssertEqual(reader.readCount, 2)
        XCTAssertEqual(tracker.fixtureAppForTesting(pid: pidA)?.windowsByID[cgWindowA]?.title, "Renamed A")
        XCTAssertEqual(tracker.fixtureAppForTesting(pid: pidB)?.windowsByID[cgWindowB]?.title, "Renamed B")
    }

    func testInFlightEventReadSuppressesPeriodicBatchForThatPid() async {
        let reader = PeriodicBatchReader(
            resultsByPID: [pidA: .success([makeSnapshot(pid: pidA, cgWindowID: cgWindowA, title: "Window")])],
            blocksTimedReads: true
        )
        let tracker = AppTracker(
            reader: reader,
            processProvider: BatchFixedProcessProvider(),
            cgSnapshotProvider: { [snapshot = cgSnapshot()] in snapshot },
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp(pid: pidA, cgWindowID: cgWindowA))

        tracker.scheduleEventReadForTesting(pid: pidA, source: .windowCreated)
        XCTAssertTrue(tracker.hasPendingEventReadForTesting(pid: pidA))

        // 事件读在途 → 本轮批读必须跳过该 pid，不注册第二个 pending。
        tracker.runPeriodicBatchForTesting(cgSnapshot: cgSnapshot())

        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pidA) }
        // 只有事件读那一次；批读没有为同 pid 排第二次。
        XCTAssertEqual(reader.readCount, 1)
    }

    func testGenerationBumpMidFlightDiscardsBatchLanding() async {
        let provider = BatchMutableProcessProvider()
        let reader = PeriodicBatchReader(
            resultsByPID: [pidA: .success([makeSnapshot(pid: pidA, cgWindowID: cgWindowA, title: "Renamed A")])],
            blocksTimedReads: true
        )
        let tracker = AppTracker(
            reader: reader,
            processProvider: provider,
            eventAXAsyncEnabled: true
        )
        tracker.installFixtureForTesting(makeApp(pid: pidA, cgWindowID: cgWindowA))

        tracker.runPeriodicBatchForTesting(cgSnapshot: cgSnapshot())
        // 读还堵在探针里，此刻换代（pid 复用）：落地必须被身份检查拦下。
        provider.advanceGeneration()
        reader.releaseOne()
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pidA) }

        XCTAssertEqual(tracker.fixtureAppForTesting(pid: pidA)?.windowsByID[cgWindowA]?.title, "Window")
    }

    func testUnreadBatchRoundLeavesSeatStateUntouched() async {
        let absence = Date(timeIntervalSince1970: 10)
        let reader = PeriodicBatchReader(resultsByPID: [pidA: .unread(.cannotComplete)])
        let tracker = AppTracker(
            reader: reader,
            processProvider: BatchFixedProcessProvider(),
            eventAXAsyncEnabled: true
        )
        var app = makeApp(pid: pidA, cgWindowID: cgWindowA)
        app.windowsByID[cgWindowA]?.isMinimized = true
        app.windowsByID[cgWindowA]?.minAbsentSince = absence
        app.shadowTabCgIDs = [91, 92]
        tracker.installFixtureForTesting(app)

        tracker.runPeriodicBatchForTesting(cgSnapshot: cgSnapshot())
        await waitUntil { !tracker.hasPendingEventReadForTesting(pid: self.pidA) }

        let after = tracker.fixtureAppForTesting(pid: pidA)
        XCTAssertEqual(after?.windowOrder, [cgWindowA])
        XCTAssertEqual(after?.windowsByID[cgWindowA]?.title, "Window")
        XCTAssertEqual(after?.windowsByID[cgWindowA]?.minAbsentSince, absence)
        XCTAssertEqual(after?.shadowTabCgIDs, [91, 92])
        XCTAssertEqual(reader.readCount, 1)
    }

    // MARK: - Fixtures

    private func cgSnapshot() -> AppTrackerCGWindowSnapshot {
        AppTrackerCGWindowSnapshot(
            allWindowIDs: [cgWindowA, cgWindowB],
            onScreenWindowIDs: [cgWindowA, cgWindowB],
            windowIDsByPID: [pidA: [cgWindowA], pidB: [cgWindowB]],
            alphaByWindowID: [:]
        )
    }

    private func makeApp(pid: pid_t, cgWindowID: CGWindowID) -> AppEntry {
        let seat = WindowEntry(
            cgWindowID: cgWindowID,
            token: "tabgrp-\(pid)-s1",
            title: "Window",
            bounds: CGRect(x: 10, y: 20, width: 500, height: 400),
            isMinimized: false,
            isFocused: true,
            everSeenVisible: true
        )
        return AppEntry(
            pid: pid,
            bundleIdentifier: "com.example.fixture\(pid)",
            appName: "Fixture\(pid)",
            activationPolicy: .regular,
            executablePath: "/Applications/Fixture.app",
            windowsByID: [cgWindowID: seat],
            windowOrder: [cgWindowID],
            isHidden: false
        )
    }

    private func makeSnapshot(pid: pid_t, cgWindowID: CGWindowID, title: String) -> AXWindowSnapshot {
        AXWindowSnapshot(
            pid: pid,
            cgWindowID: cgWindowID,
            titleRead: .value(title),
            bounds: CGRect(x: 10, y: 20, width: 500, height: 400),
            role: kAXWindowRole as String,
            subrole: kAXStandardWindowSubrole as String,
            isMinimized: false,
            isFocusedWindow: true,
            element: AXUIElementCreateApplication(pid)
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition(), DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

/// 可注入按 pid 定制结果的限时读探针；可选在读中阻塞（模拟批读在途窗口）。
private final class PeriodicBatchReader: AppTrackerWindowReading, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var count = 0
    private let resultsByPID: [pid_t: AXWindowReadResult]
    private let blocksTimedReads: Bool

    init(resultsByPID: [pid_t: AXWindowReadResult], blocksTimedReads: Bool = false) {
        self.resultsByPID = resultsByPID
        self.blocksTimedReads = blocksTimedReads
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func releaseOne() {
        semaphore.signal()
    }

    func windows(forPID pid: pid_t) -> [AXWindowSnapshot] { [] }

    func windowReadResult(forPID pid: pid_t) -> AXWindowReadResult {
        resultsByPID[pid] ?? .unread(.cannotComplete)
    }

    func inventoryWindows(forPID pid: pid_t, messagingTimeout: TimeInterval) -> AXWindowReadResult {
        lock.lock()
        count += 1
        lock.unlock()
        if blocksTimedReads { semaphore.wait() }
        return resultsByPID[pid] ?? .unread(.cannotComplete)
    }
}

private struct BatchFixedProcessProvider: AppTrackerProcessProviding {
    func isAlive(pid: pid_t) -> Bool { true }

    func identity(pid: pid_t, bundleID: String?) -> ScanAdmissionDecision.ProcessIdentity {
        ScanAdmissionDecision.ProcessIdentity(pid: pid, startTimeSec: 1, startTimeUsec: 2, bundleID: bundleID)
    }
}

private final class BatchMutableProcessProvider: AppTrackerProcessProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var generation: Int64 = 1

    func advanceGeneration() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    func isAlive(pid: pid_t) -> Bool { true }

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

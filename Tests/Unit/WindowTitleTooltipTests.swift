import AppKit
import XCTest

final class WindowTitleTooltipTests: XCTestCase {
    func testFontUsesRenderedSizeRules() {
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 0.5).pointSize, 10)
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 1).pointSize, 12)
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 1.5).pointSize, 18)
    }

    func testFontUsesRoundedSystemDesign() {
        XCTAssertTrue(WindowTitleTextMetrics.font(scale: 1).fontName.contains("Rounded"))
    }

    func testIntrinsicWidthTracksScale() {
        let title = "activity-list.vue - project"
        let small = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 0.5)
        let regular = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 1)
        let large = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 1.5)

        XCTAssertLessThan(small, regular)
        XCTAssertLessThan(regular, large)
    }

    func testTooltipThresholdTracksDockScaleButBubbleDoesNot() {
        // 条内标题宽度随任务条缩放，截断判定必须用同一个宽度——两处各写死 140 就会出现
        // 「看着截断了却不弹 tooltip」（或反之）。
        for scale in [0.846153846, 1.0, 1.153846154, 1.307692308] as [CGFloat] {
            XCTAssertEqual(WindowTitleTextMetrics.maximumWidth(for: scale),
                           WindowTitleTextMetrics.maximumWidth * scale, accuracy: 0.001)
        }
        // 中档必须与历史字面值一致。气泡面板本身不缩（独立表面），这里只锁条内那段。
        XCTAssertEqual(WindowTitleTextMetrics.maximumWidth(for: 1.0), 140)
    }

    func testTruncationThresholdIncludesTolerance() {
        XCTAssertFalse(WindowTitleTextMetrics.isTruncated(intrinsicWidth: 142))
        XCTAssertTrue(WindowTitleTextMetrics.isTruncated(intrinsicWidth: 142.01))
    }

    func testEmptyAndShortTitlesDoNotNeedTooltip() {
        XCTAssertFalse(WindowTitleTextMetrics.needsTooltip(for: "", scale: 1))
        XCTAssertFalse(WindowTitleTextMetrics.needsTooltip(for: "Short", scale: 1))
    }

    func testLongTitleNeedsTooltip() {
        XCTAssertTrue(WindowTitleTextMetrics.needsTooltip(
            for: String(repeating: "Window title ", count: 20),
            scale: 1
        ))
    }
}

/// 悬停几何的回归锁。这些断言**直接对着改造前那套 `VStack(spacing: 2)` 的布局公式**写，
/// 而不是抄实现里的常量——否则实现改错时测试跟着一起错，等于没测。
///
/// 旧布局（`s` = scale，`Hs` = 副标题行高，注意那个 `spacing: 2` 是**不缩放**的）：
///   静息 `[Spacer, 2, pill(34s), 2, Spacer]`，总高 `52s`
///   悬停 `[Spacer, 2, pill(28s), 2, sub(Hs), 2, Spacer]`
final class ChipSubtitleMetricsTests: XCTestCase {
    private let tiers: [CGFloat] = [44.0 / 52, 1, 60.0 / 52, 68.0 / 52]   // 小 / 中 / 大 / 特大

    /// 旧布局里静息态药丸的顶边（两个不缩放的 2 正好抵消，恰好是 9s）。
    private func legacyRestPillTop(_ s: CGFloat) -> CGFloat { 9 * s }

    /// 旧布局里悬停态药丸的顶边。
    private func legacyHoverPillTop(_ s: CGFloat) -> CGFloat {
        let spacer = (52 * s - 2 - 28 * s - 2 - ChipSubtitleMetrics.rowHeight(for: s) - 2) / 2
        return spacer + 2
    }

    /// 旧布局里悬停态副标题的**竖向中心**。
    private func legacyHoverSubtitleCenter(_ s: CGFloat) -> CGFloat {
        legacyHoverPillTop(s) + 28 * s + 2 + ChipSubtitleMetrics.rowHeight(for: s) / 2
    }

    func testRestPillTopIsUnchangedByTheNewFixedHeightBox() {
        for s in tiers {
            // 新结构：spacing 0，两个 Spacer 平分 52s - 34s，药丸盒顶边恒为 9s，静息不再位移。
            let newTop = (ChipPillMetrics.chipHeight - ChipPillMetrics.boxHeight) / 2 * s
            XCTAssertEqual(newTop, legacyRestPillTop(s), accuracy: 0.001,
                           "静息态药丸顶边必须逐像素不变（scale=\(s)）")
        }
    }

    func testHoverPillShiftReproducesLegacyLayout() {
        for s in tiers {
            let newTop = 9 * s + ChipSubtitleMetrics.pillHoverShift(for: s)
            XCTAssertEqual(newTop, legacyHoverPillTop(s), accuracy: 0.001,
                           "悬停态药丸顶边必须与旧布局一致（scale=\(s)）")
        }
    }

    func testSubtitleShiftReproducesLegacyLayoutAndIsIndependentOfRowHeight() {
        for s in tiers {
            // 新结构：零高基线在 43s，文字以基线为中心。
            let newCenter = 43 * s + ChipSubtitleMetrics.subtitleShift(for: s)
            XCTAssertEqual(newCenter, legacyHoverSubtitleCenter(s), accuracy: 0.001,
                           "悬停态副标题中心必须与旧布局一致（scale=\(s)）")
        }
    }

    /// 位移量**不是** `k * scale` 的形状——旧布局里那个不缩放的 `spacing: 2` 决定的。
    /// 这条专门挡住"看着像比例关系就写成乘法"的回归（中档上两者恰好相等，只有别的档能发现）。
    func testShiftsAreNotProportionalToScale() {
        XCTAssertEqual(ChipSubtitleMetrics.subtitleShift(for: 1), -2, accuracy: 0.001)
        XCTAssertNotEqual(ChipSubtitleMetrics.subtitleShift(for: 68.0 / 52), -2 * 68.0 / 52, accuracy: 0.05)
    }

    func testSubtitleFontMatchesRenderedRules() {
        XCTAssertEqual(ChipSubtitleMetrics.font(scale: 0.5).pointSize, 8)   // max(8, 9*0.5)
        XCTAssertEqual(ChipSubtitleMetrics.font(scale: 1).pointSize, 9)
        XCTAssertEqual(ChipSubtitleMetrics.font(scale: 1.5).pointSize, 13.5)
        XCTAssertTrue(ChipSubtitleMetrics.font(scale: 1).fontName.contains("Rounded"))
    }

    func testSubtitleWidthIsADefiniteInterpolatableValue() {
        XCTAssertEqual(ChipSubtitleMetrics.width(of: "", scale: 1), 0, "空名不占宽度")
        let latin = ChipSubtitleMetrics.width(of: "Safari", scale: 1)
        let cjk = ChipSubtitleMetrics.width(of: "访达", scale: 1)
        XCTAssertGreaterThan(latin, 0)
        XCTAssertGreaterThan(cjk, 0)
    }

    func testSubtitleWidthClampsToTheMaximum() {
        let long = String(repeating: "超长应用名", count: 40)
        for s in tiers {
            XCTAssertEqual(ChipSubtitleMetrics.width(of: long, scale: s),
                           ChipSubtitleMetrics.maximumWidth(for: s), accuracy: 0.001,
                           "撞上限后必须正好等于上限（scale=\(s)）")
        }
    }

    func testSubtitleWidthTracksScale() {
        XCTAssertLessThan(ChipSubtitleMetrics.width(of: "Safari", scale: 0.5),
                          ChipSubtitleMetrics.width(of: "Safari", scale: 1.5))
    }
}

/// 探针改量卡片矩形之后，tooltip 的锚点契约（pill rect）靠这组常量推出来，
/// 所以推导必须与渲染用的是同一份数值。
final class ChipPillMetricsTests: XCTestCase {
    func testWidthMatchesTheRenderedComposition() {
        let title = "psd-文件"
        let scale: CGFloat = 1
        let titleWidth = min(WindowTitleTextMetrics.intrinsicWidth(of: title, scale: scale),
                             WindowTitleTextMetrics.maximumWidth(for: scale))
        let expected = (2 * 10 + 22 + 6) * scale + ceil(titleWidth)
        XCTAssertEqual(ChipPillMetrics.width(title: title, scale: scale), expected, accuracy: 0.001)
    }

    func testWidthIsCappedByTheTitleMaximum() {
        let long = String(repeating: "very-long-window-title-", count: 20)
        let scale: CGFloat = 1
        let expected = (2 * 10 + 22 + 6) * scale + ceil(WindowTitleTextMetrics.maximumWidth(for: scale))
        XCTAssertEqual(ChipPillMetrics.width(title: long, scale: scale), expected, accuracy: 0.001)
    }

    /// 药丸在卡内水平居中 → midX 直接沿用卡片的；竖向全部来自常量。
    func testPillRectIsHorizontallyCenteredOnTheCard() {
        let card = CGRect(x: 100, y: 200, width: 180, height: 52)
        let rect = ChipPillMetrics.pillRect(inCard: card, title: "psd-文件", hovered: false, scale: 1)
        XCTAssertEqual(rect.midX, card.midX, accuracy: 0.001)
    }

    /// 屏幕坐标 y 向上：静息态药丸顶边 = 卡片顶边下方 9pt。
    func testRestPillRectSitsNinePointsBelowTheCardTop() {
        let card = CGRect(x: 0, y: 0, width: 180, height: 52)
        let rect = ChipPillMetrics.pillRect(inCard: card, title: "psd-文件", hovered: false, scale: 1)
        XCTAssertEqual(rect.maxY, card.maxY - 9, accuracy: 0.001)
        XCTAssertEqual(rect.height, 34, accuracy: 0.001)
    }

    func testHoverPillRectUsesTheHoverShift() {
        let card = CGRect(x: 0, y: 0, width: 180, height: 52)
        let rect = ChipPillMetrics.pillRect(inCard: card, title: "psd-文件", hovered: true, scale: 1)
        XCTAssertEqual(rect.maxY, card.maxY - 9 - ChipSubtitleMetrics.pillHoverShift(for: 1), accuracy: 0.001)
        XCTAssertEqual(rect.height, 28, accuracy: 0.001)
    }
}

final class ChipHoverVisualTests: XCTestCase {
    private let tiers: [CGFloat] = [44.0 / 52, 1, 60.0 / 52, 68.0 / 52]

    func testEndpointsMatchTheExistingRestAndHoverMetricsAtEveryTier() {
        for scale in tiers {
            let subtitleWidth = ChipSubtitleMetrics.width(of: "Safari", scale: scale)
            let rest = ChipHoverVisual.resolve(progress: 0, scale: scale, subtitleNaturalWidth: subtitleWidth)
            let hover = ChipHoverVisual.resolve(progress: 1, scale: scale, subtitleNaturalWidth: subtitleWidth)

            XCTAssertEqual(rest.bareIconSize, 36 * scale, accuracy: 0.001)
            XCTAssertEqual(hover.bareIconSize, 24 * scale, accuracy: 0.001)
            XCTAssertEqual(rest.pillHeight, ChipPillMetrics.height(hovered: false, scale: scale), accuracy: 0.001)
            XCTAssertEqual(hover.pillHeight, ChipPillMetrics.height(hovered: true, scale: scale), accuracy: 0.001)
            XCTAssertEqual(rest.pillIconSize, 22 * scale, accuracy: 0.001)
            XCTAssertEqual(hover.pillIconSize, 18 * scale, accuracy: 0.001)
            XCTAssertEqual(rest.pillShift, 0, accuracy: 0.001)
            XCTAssertEqual(hover.pillShift, ChipSubtitleMetrics.pillHoverShift(for: scale), accuracy: 0.001)
            XCTAssertEqual(rest.subtitleSlotWidth, 0, accuracy: 0.001)
            XCTAssertEqual(hover.subtitleSlotWidth, subtitleWidth, accuracy: 0.001)
            XCTAssertEqual(rest.subtitleOpacity, 0, accuracy: 0.001)
            XCTAssertEqual(hover.subtitleOpacity, 1, accuracy: 0.001)
        }
    }

    func testProgressClampsAndAllHoverQuantitiesShareIt() {
        let low = ChipHoverVisual.resolve(progress: -2, scale: 1, subtitleNaturalWidth: 100)
        let middle = ChipHoverVisual.resolve(progress: 0.4, scale: 1, subtitleNaturalWidth: 100)
        let high = ChipHoverVisual.resolve(progress: 2, scale: 1, subtitleNaturalWidth: 100)

        XCTAssertEqual(low.progress, 0)
        XCTAssertEqual(high.progress, 1)
        XCTAssertEqual(middle.subtitleOpacity, 0.4, accuracy: 0.001)
        XCTAssertEqual(middle.emphasisProgress, 0.4, accuracy: 0.001)
        XCTAssertEqual(middle.subtitleSlotWidth, 40, accuracy: 0.001)
        XCTAssertEqual(middle.pillHeight, 31.6, accuracy: 0.001)
    }
}

final class ScreenRectReaderTests: XCTestCase {
    private final class Task: ScreenRectDeliveryTask {
        private let action: () -> Void
        private(set) var isCancelled = false

        init(action: @escaping () -> Void) { self.action = action }
        func cancel() { isCancelled = true }
        func run() { if !isCancelled { action() } }
        func forceRun() { action() }
    }

    private final class Scheduler: ScreenRectDeliveryScheduling {
        struct Scheduled {
            let delay: TimeInterval
            let task: Task
        }

        private(set) var scheduled: [Scheduled] = []

        func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> ScreenRectDeliveryTask {
            let task = Task(action: action)
            scheduled.append(Scheduled(delay: delay, task: task))
            return task
        }

        func runAll() {
            let tasks = scheduled
            scheduled.removeAll()
            tasks.forEach { $0.task.run() }
        }
    }

    func testImmediateModeReportsEveryDistinctRectInOrder() {
        let scheduler = Scheduler()
        var reported: [CGRect] = []
        let view = ScreenRectReader.TrackingView(
            delivery: .root, scheduler: scheduler, onChange: { reported.append($0) }
        )
        let a = CGRect(x: 1, y: 2, width: 3, height: 4)
        let b = CGRect(x: 2, y: 3, width: 4, height: 5)

        view.enqueue(a)
        view.enqueue(a)
        view.enqueue(b)
        view.enqueue(a)
        scheduler.runAll()

        XCTAssertEqual(reported, [a, b, a])
        XCTAssertEqual(scheduler.scheduled.count, 0)
    }

    func testDebounceReportsOnlyTheLatestRectAfterSettleInterval() {
        let scheduler = Scheduler()
        var reported: [CGRect] = []
        let view = ScreenRectReader.TrackingView(
            delivery: .tooltip, scheduler: scheduler, onChange: { reported.append($0) }
        )
        let a = CGRect(x: 1, y: 2, width: 3, height: 4)
        let b = CGRect(x: 2, y: 3, width: 4, height: 5)

        view.enqueue(a)
        view.enqueue(b)
        XCTAssertEqual(scheduler.scheduled.map(\.delay), [0.05, 0.05])
        scheduler.runAll()

        XCTAssertEqual(reported, [b])
    }

    func testDebounceGenerationRejectsAnOldTaskEvenWhenCancellationArrivesTooLate() {
        let scheduler = Scheduler()
        var reported: [CGRect] = []
        let view = ScreenRectReader.TrackingView(
            delivery: .tooltip, scheduler: scheduler, onChange: { reported.append($0) }
        )
        let old = CGRect(x: 1, y: 2, width: 3, height: 4)
        let latest = CGRect(x: 2, y: 3, width: 4, height: 5)

        view.enqueue(old)
        let oldTask = scheduler.scheduled[0].task
        view.enqueue(latest)
        oldTask.forceRun()
        scheduler.scheduled[1].task.forceRun()

        XCTAssertEqual(reported, [latest])
    }

    func testPendingDeliveryUsesTheLatestCallback() {
        let scheduler = Scheduler()
        var old: [CGRect] = []
        var latest: [CGRect] = []
        let view = ScreenRectReader.TrackingView(
            delivery: .tooltip, scheduler: scheduler, onChange: { old.append($0) }
        )
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)

        view.enqueue(rect)
        view.update(delivery: .tooltip, onChange: { latest.append($0) })
        scheduler.runAll()

        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(latest, [rect])
    }

    func testDetachCancellationBlocksImmediateAndDebouncedCallbacks() {
        for delivery in [ScreenRectReader.Delivery.root, .tooltip] {
            let scheduler = Scheduler()
            var reported: [CGRect] = []
            let view = ScreenRectReader.TrackingView(
                delivery: delivery, scheduler: scheduler, onChange: { reported.append($0) }
            )
            view.enqueue(CGRect(x: 1, y: 2, width: 3, height: 4))
            view.cancelPendingDelivery()
            scheduler.runAll()
            XCTAssertTrue(reported.isEmpty, "cancel must block \(delivery)")
        }
    }

    func testChangingDeliveryCancelsTheOldModeAndAllowsTheNewMode() {
        let scheduler = Scheduler()
        var reported: [CGRect] = []
        let view = ScreenRectReader.TrackingView(
            delivery: .tooltip, scheduler: scheduler, onChange: { reported.append($0) }
        )
        let old = CGRect(x: 1, y: 2, width: 3, height: 4)
        let latest = CGRect(x: 2, y: 3, width: 4, height: 5)

        view.enqueue(old)
        view.update(delivery: .root, onChange: { reported.append($0) })
        view.enqueue(latest)
        scheduler.runAll()

        XCTAssertEqual(reported, [latest])
    }

    func testCallSiteDeliveryPoliciesStayExplicit() {
        XCTAssertEqual(ScreenRectReader.Delivery.root, .immediateDeduplicated)
        XCTAssertEqual(ScreenRectReader.Delivery.tooltip, .debounced(settleInterval: 0.05))
    }
}

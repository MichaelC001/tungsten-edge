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

    // 截断判定（`isTruncated` / `needsTooltip`）连同它的三条测试于 2026-08-17 删除：
    // 那是「标题被截断才弹 tooltip」的门槛，气泡先改成悬停就弹、后又改成只写应用名，
    // 生产代码里已无调用方。别按旧签名把它们恢复回来。
}

/// 悬停时 chip 的几何**恒定不动**——应用名 2026-08-16 改成了原生 Dock 那种「图标正上方的
/// 气泡」，chip 内部不再需要为它腾地方。
///
/// 这里以前锁的是 `ChipSubtitleMetrics` 那套位移公式（对着更早的 `VStack(spacing: 2)` 布局
/// 解方程得来的 `pillHoverShift = 3s - 1 - Hs/2` 之类）。**那个类型和它的整组测试随功能
/// 一起删除了，不要按旧公式恢复。**
final class ChipHoverGeometryTests: XCTestCase {
    private let tiers: [CGFloat] = DockSize.allCases.map(\.scale)

    func testHoverDoesNotMoveAnyGeometry() {
        for scale in tiers {
            let rest = ChipHoverVisual.resolve(progress: 0, scale: scale)
            let hover = ChipHoverVisual.resolve(progress: 1, scale: scale)
            XCTAssertEqual(rest.bareIconSize, hover.bareIconSize, accuracy: 0.001,
                           "悬停不该缩图标（scale=\(scale)）")
            XCTAssertEqual(rest.pillHeight, hover.pillHeight, accuracy: 0.001,
                           "悬停不该缩药丸（scale=\(scale)）")
            XCTAssertEqual(rest.pillIconSize, hover.pillIconSize, accuracy: 0.001,
                           "悬停不该缩药丸内的图标（scale=\(scale)）")
        }
    }

    /// 唯一还随悬停变化的量：药丸底与描边的提亮。
    func testOnlyEmphasisTracksHover() {
        XCTAssertEqual(ChipHoverVisual.resolve(progress: 0, scale: 1).emphasisProgress, 0)
        XCTAssertEqual(ChipHoverVisual.resolve(progress: 1, scale: 1).emphasisProgress, 1)
        XCTAssertEqual(ChipHoverVisual.resolve(progress: 0.5, scale: 1).emphasisProgress, 0.5)
    }

    func testProgressIsClamped() {
        XCTAssertEqual(ChipHoverVisual.resolve(progress: -3, scale: 1).progress, 0)
        XCTAssertEqual(ChipHoverVisual.resolve(progress: 9, scale: 1).progress, 1)
    }

    func testSizesTrackTheTier() {
        for scale in tiers {
            let v = ChipHoverVisual.resolve(progress: 0, scale: scale)
            XCTAssertEqual(v.bareIconSize, ChipPillMetrics.bareIconSlot * scale, accuracy: 0.001)
            XCTAssertEqual(v.pillHeight, ChipPillMetrics.boxHeight * scale, accuracy: 0.001)
            XCTAssertEqual(v.pillIconSize, ChipPillMetrics.iconSlot * scale, accuracy: 0.001)
        }
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
        let rect = ChipPillMetrics.pillRect(inCard: card, title: "psd-文件", scale: 1)
        XCTAssertEqual(rect.midX, card.midX, accuracy: 0.001)
    }

    /// 屏幕坐标 y 向上：静息态药丸顶边 = 卡片顶边下方 `boxTopInset`。
    func testRestPillRectSitsBoxTopInsetBelowTheCardTop() {
        let card = CGRect(x: 0, y: 0, width: 180, height: ChipPillMetrics.chipHeight)
        let rect = ChipPillMetrics.pillRect(inCard: card, title: "psd-文件", scale: 1)
        XCTAssertEqual(rect.maxY, card.maxY - ChipPillMetrics.boxTopInset, accuracy: 0.001)
        XCTAssertEqual(rect.height, 34, accuracy: 0.001)
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

    /// 气泡尺寸是 2026-08-17 从原生 macOS 26 Dock 的截图上逐像素量出来的，不是设计出来的。
    /// 这条锁住那组数——要改先重新截图重新量，别凭手感调。
    func testBubbleMetricsMatchTheMeasuredNativeDockLabel() {
        XCTAssertEqual(WindowTitleTooltipStyle.height, 26)
        XCTAssertEqual(WindowTitleTooltipStyle.fontSize, 14)
        XCTAssertEqual(WindowTitleTooltipStyle.horizontalPadding, 13)
        XCTAssertEqual(WindowTitleTooltipStyle.tailWidth, 23)
        XCTAssertEqual(WindowTitleTooltipStyle.tailHeight, 6.5)
        // 中段直边的斜率（半宽/深度）实测 ≈1.17；圆头存在的证据就是它外推不到底。
        let slope = (WindowTitleTooltipStyle.tailShoulderHalfWidth - WindowTitleTooltipStyle.tailTipHalfWidth)
            / (WindowTitleTooltipStyle.tailTipDepth - WindowTitleTooltipStyle.tailShoulderDepth)
        XCTAssertEqual(slope, 1.17, accuracy: 0.05)
        let extrapolated = WindowTitleTooltipStyle.tailTipDepth + WindowTitleTooltipStyle.tailTipHalfWidth / slope
        XCTAssertGreaterThan(extrapolated, WindowTitleTooltipStyle.tailHeight,
                             "直边外推必须落在实际尖端之下——差的那截才是圆头")
        // **胶囊，不是圆角矩形**：圆角必须正好是高的一半。
        XCTAssertEqual(WindowTitleTooltipStyle.cornerRadius, WindowTitleTooltipStyle.height / 2)
        // 间距量的是**尖端**到条顶，气泡自己的高度已经含尖角。
        XCTAssertEqual(PanelGeometry.windowTitleTooltipGap, WindowTitleTooltipStyle.tipGap)
    }

    /// 尖角必须画在同一条闭合路径里：叠一个三角形会在接缝处交叉出一条横线。
    /// 这里验证形状确实向下伸出尖角，且尖端落在水平中心。
    func testShapeExtendsADownwardTailAtTheHorizontalCentre() {
        let rect = CGRect(x: 0, y: 0, width: 85, height: 26 + WindowTitleTooltipStyle.tailHeight)
        let box = WindowTitleTooltipShape().path(in: rect).boundingRect
        XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.5, "尖端要顶到形状底边")
        XCTAssertEqual(box.width, rect.width, accuracy: 0.5, "主体要占满整宽")

        // 尖端所在那一行只剩很窄一条，且居中。
        let tip = WindowTitleTooltipShape().path(in: rect)
        let nearTip = tip.boundingRect
        XCTAssertEqual(nearTip.midX, rect.midX, accuracy: 0.5)
        XCTAssertFalse(tip.contains(CGPoint(x: rect.minX + 2, y: rect.maxY - 1)),
                       "尖角两侧必须是空的，不能是一整条底边")
        XCTAssertTrue(tip.contains(CGPoint(x: rect.midX, y: rect.maxY - 1)),
                      "中心那一竖必须还在形状里")
    }
}

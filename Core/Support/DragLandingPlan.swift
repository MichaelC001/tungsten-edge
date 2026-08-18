import CoreGraphics
import Foundation

/// 松手后浮动副本「飞回卡槽」的一次飞行。坐标都在**载体面板内**（左上原点、y 向下），
/// 因为载体是唯一会画它的地方。
struct DragLandingFlight: Equatable {
    let from: CGPoint
    let to: CGPoint
    let fromScale: CGFloat
    let toScale: CGFloat
    /// **这一次**飞多久。按距离算出来的，不是全局常量——见 `DragLandingPlan.duration(travel:)`。
    let duration: TimeInterval
}

/// 归位飞行的纯判定（owner 2026-08-18：「放手一瞬间图标归位的动画，做的不如原生 dock 从容优雅」）。
///
/// **改造前根本没有这个阶段**：`endDrag()` 里 `orderOut` 载体和 `draggingPayload = nil` 发生在同一帧，
/// 于是手里的浮动副本瞬间消失、条上那张卡瞬间从 opacity 0 变 1。光标到卡槽中心那段距离、
/// 还有 1.05 → 1.0 的尺寸差，全是**跳**过去的。原生 Dock 是让图标飞回卡槽。
///
/// 判定单独抽出来的理由和 `DragConversionPlan` / `StripHoverResolution` 一样：
/// 坐标换算最容易写岔（屏幕是左下原点、载体面板是左上原点），单测能钉死它。
enum DragLandingPlan {
    /// 飞行时长的两端。**时长按距离取，不是定值**（owner 2026-08-18：「没有原生的动画从容优雅」）。
    ///
    /// 定长的毛病在于：同一个 0.26 秒，20pt 的小归位显得急促、200pt 的长途显得赶。
    /// 原生那种「从容」很大程度来自距离越远走得越久。开根号收敛而不是线性：
    /// 近距离不至于短到看不见，远距离也不会拖沓。
    /// owner 逐轮定的：0.16/0.34 → 0.22/0.46 → 0.30/0.62 → **0.60/0.90**（2026-08-18 第四轮点名的数）。
    static let minimumDuration: TimeInterval = 0.60
    static let maximumFlightDuration: TimeInterval = 0.90
    /// 到这个位移就用满时长；再远也不加了。
    static let referenceTravel: CGFloat = 300

    /// **位移小于这个数就不飞，直接落定。**
    ///
    /// 起拖门槛本来就是 8pt，所以「按下去手抖了十来 pt 就松开」本质上是一次点击，不是拖动。
    /// 让它也走归位飞行的话，一个几乎零距离的动画要占满 `minimumDuration`——时长从 0.16s
    /// 调到 0.60s 之后，这种原地慢慢晃回去的半透明影子就看得一清二楚了
    ///（owner 2026-08-18：「点击图标隔壁的图标会有上下的重影」——那正是上一次点击留下的
    /// 0.6 秒归位还没飞完，而鼠标已经移到隔壁去了）。
    ///
    /// 门槛取 12pt：比起拖门槛 8pt 略大一点，正好把「点击时的手抖」挡在外面。
    static let minimumTravel: CGFloat = 12

    /// 兜底/基准时长（纠偏闸与单测用的名义值）。真正每次飞多久看 `duration(travel:)`。
    static let duration: TimeInterval = 0.26

    static func duration(travel: CGFloat) -> TimeInterval {
        let ratio = min(1, max(0, Double(travel) / Double(referenceTravel)))
        return minimumDuration + (maximumFlightDuration - minimumDuration) * ratio.squareRoot()
    }

    /// 载体到点之后再等一小会儿才真的收掉，给最后一帧提交留余量。
    static let settleMargin: TimeInterval = 0.03

    /// 中途纠偏会把收载体的时刻往后推（每纠一次就重新飞一段）。这是整段飞行的硬上限，
    /// 免得卡槽一直在动时载体挂着不放。正常情况根本用不到：松手时不重排，卡槽是静止的。
    static let maximumDuration: TimeInterval = 2.00

    /// **交接淡出**：飞行到点之后，条上那张卡先显形，载体再用这段时间淡掉。
    ///
    /// 为什么不能直接 `orderOut`（owner 2026-08-18 报「落地有几率抖，不到一半的概率」）：
    /// 清掉飞行只是让 SwiftUI 去**排**一次更新，卡要到下一轮 run loop 才真的显形。
    /// 谁先谁后是赛跑——赢了是两边短暂重叠（看不出来），输了是两边都没有（闪一下）。
    /// 「有几率」正是赛跑的特征。改成显式两步之后不再有赛跑；淡出顺带解决了
    /// 载体有投影、卡没有投影，撤掉那一下投影会「啵」地消失的问题。
    static let handoffFade: TimeInterval = 0.09

    /// 离飞行上限不足一整段时长时就别再纠偏了：那时候重新起飞一段必然会被上限截断，
    /// 反而制造出要治的那一下跳。
    static func allowsRetarget(remainingBeforeDeadline: TimeInterval,
                               flightDuration: TimeInterval = duration) -> Bool {
        remainingBeforeDeadline > flightDuration + settleMargin
    }

    /// **必须是定时长曲线，不能用 spring**（owner 2026-08-18 一眼看出「归位还是会抖」）。
    ///
    /// `spring(response: 0.26)` 在 0.26 秒时**根本没停**——response 只是它的固有周期，
    /// 真正静止要 2~3 倍时长。而收载体的计时器是按 `duration` 掐的，于是图标飞到一半被
    /// 硬切掉，剩下那段距离由「载体消失、条上卡显形」一步跳完，看着就是抖一下。
    ///
    /// 控制点取仓库里既有的那条「快出缓停」（`PopoverAnimation.curve()` 同款）：
    /// 起步快、收尾缓，正是原生 Dock 归位的读感，而且**在 `duration` 处确实结束**。
    static let curve = (c0x: 0.2, c0y: 0.9, c1x: 0.3, c1y: 1.0)

    /// 副本宿主视图的固定尺寸。**故意不按内容量**：量尺寸得先等 SwiftUI 把新载荷布局出来，
    /// 又是一次时序赌博；而这块宿主透明、不吃鼠标，开大一点零代价。
    /// 够装下最大档位的带标题卡片 + 投影 + 放大到 1.05 的余量。
    static let carrierHostSize = CGSize(width: 360, height: 200)

    /// 拎在手里时的放大倍数（`DragCarrierView` 的常驻状态）。
    static let carriedScale: CGFloat = 1.05
    /// 悬在投放区（胶囊 / 任务条）时缩到的倍数。
    static let dropZoneScale: CGFloat = 0.82
    /// 落地即与条上那张卡同尺寸。
    static let landedScale: CGFloat = 1.0

    /// 屏幕矩形（左下原点）→ 载体面板内的中心点（左上原点）。
    ///
    /// - Parameter anchorScreenRect: 这一项最终会落在屏幕上的哪一格。`nil` = 不知道 → 不飞，
    ///   走改造前的瞬时收尾（零风险的退路）。转正进任务条那一支就是这种：松手会解冻任务条宽度、
    ///   整条重新居中，落点在飞行途中还会漂。
    static func flight(from: CGPoint,
                       fromScale: CGFloat,
                       anchorScreenRect: CGRect?,
                       carrierScreenFrame: CGRect) -> DragLandingFlight? {
        guard let rect = anchorScreenRect,
              rect.width > 0, rect.height > 0,
              carrierScreenFrame.width > 0, carrierScreenFrame.height > 0 else { return nil }
        let to = CGPoint(x: rect.midX - carrierScreenFrame.minX,
                         y: carrierScreenFrame.maxY - rect.midY)
        // 几乎没动过 → 不飞（理由见 `minimumTravel`）。
        guard hypot(to.x - from.x, to.y - from.y) >= minimumTravel else { return nil }
        return DragLandingFlight(from: from, to: to,
                                 fromScale: fromScale, toScale: landedScale,
                                 duration: duration(travel: hypot(to.x - from.x, to.y - from.y)))
    }
}

/// 归位飞行的开关。新手感一律带退路（同 `ChipPressSwitches`）：万一在实机上和重排、
/// 跨面板收纳打架，owner 能立刻退回瞬时收尾，不用等重新打包。
enum DragLandingSwitches {
    static let enabled = ProcessInfo.processInfo.environment["DOCK_DRAG_LANDING"] != "0"
}

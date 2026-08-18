import AppKit
import Combine
import SwiftUI

// `DragSource` 定义在 Core/Support/DragConversionPlan.swift（纯决策层，测试 target 本地编译）。

/// 载体面板的容器。普通透明视图，只为了不让 `NSHostingView` 直接当 `contentView`
///（AGENTS 那条护栏），顺带让「摆位置」变成改一个子视图的 frame。
private final class CarrierContainerView: NSView {}

/// 载体（飘浮副本）画成什么样。
enum DragVisualKind { case stripChip, drawerIcon, folderChip, keptAppIcon, messagingIcon }

/// 通用拖动载荷。任务条卡片有 `StripItem`；抽屉很多图标（无窗口运行项 / 未运行收纳项 / 纯固定项）
/// 只有 bundleID、没有 `StripItem`，故 `item` 可空，主键统一用 `bundleID`。`id` 给来源面板自己
/// 排序用（strip = chip 身份令牌 `item.id`，drawer = bundleID），免得来源面板从载荷里猜。
struct DragPayload {
    let source: DragSource
    let id: String          // strip = item.id（chip token）；drawer = bundleID
    let bundleID: String
    let item: StripItem?     // 仅任务条窗口卡有
    let visualKind: DragVisualKind
    /// 能否投到「另一面板」触发收纳/移回。strip = `canStash`；drawer = 真收纳项（`drawerStore.contains`）。
    /// 纯固定项 = false：只能抽屉内排序，拖到任务条不高亮、不动作（Codex 二审）。
    let canExternalDrop: Bool
}

/// 跨面板拖动的唯一权威（拖卡进抽屉 路线 C / 抽屉拖回任务条，2026-06-20→21）。
///
/// 对称两向：任务条卡拖到胶囊=收纳；抽屉图标拖到任务条=移回。整屏自绘载体 + local 监视器一套机制
/// 反向复用（机制探针 2026-06-20 已验证：mouse-down 起拖后隐式抓取使 local 监视器全程接事件含松手）。
/// 全部收在这里：载体面板生命周期、监视器、落点判定、幂等收尾。来源面板只 `beginDrag` + 读
/// `draggingPayload`（隐藏原位）/ `isOverDropZone`（停区内排序）。
@MainActor
final class DragController: ObservableObject {
    @Published private(set) var draggingPayload: DragPayload?
    @Published private(set) var isOverDropZone = false

    /// 拖动中的光标位置（屏幕坐标）。**刻意不是 `@Published`。**
    ///
    /// 实测 2026-08-18（`DOCK_HOVER_TRACE`）：它曾经是 `@Published`，而 `DockStripView`
    /// 用 `@EnvironmentObject` 订阅着本对象——于是**每动一下鼠标就把整条任务条打翻重算一次**，
    /// 一秒钟拖动量到 **46 次整条 body 重算**（每次都要重建整份投影：快照转卡、成员投影、顺序对账）。
    /// 主线程被这些占满，载体的位置更新就迟到，快速拖动时甚至丢帧——正是 owner 报的
    /// 「起拖有迟滞」「拖快了图标会短暂消失」。
    ///
    /// 现在改成：值本身是普通属性，变化通过 `pointerMoves` 广播。
    /// - 载体的**位置**根本不再经过 SwiftUI —— `update()` 直接设宿主视图的 frame（见 `placeCarrier`）。
    /// - 需要**每帧跑副作用**的（条内重排、跨面板转换）→ 用 `.onReceive(pointerMoves)`：
    ///   闭包照跑，但不给视图建立依赖，只有副作用真的改了什么才会重画。
    private(set) var globalLocation: CGPoint = .zero
    private let pointerSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    /// **存成 `let`，不要每次调用现 erase**：SwiftUI 的 `onReceive` 换了 publisher 实例就会重订阅，
    /// 而 `CurrentValueSubject` 一订阅就补发当前值，等于每次 body 都白跑一遍副作用。
    let pointerMoves: AnyPublisher<CGPoint, Never>

    private(set) var grabOffset: CGSize = .zero
    private(set) var carrierScreenFrame: CGRect = .zero

    // MARK: - 松手归位飞行

    /// 松手之后、载体真正消失之前的那 0.26 秒：浮动副本从光标飞回卡槽。
    /// 见 `DragLandingPlan`。`nil` = 没有飞行在进行（含被关掉、拿不到落点两种）。
    struct Landing: Equatable {
        /// 每次飞行一个新令牌：视图靠它做 `.id()`，连着两次拖动才不会复用同一个动画状态。
        let token: Int
        let payload: DragPayload
        let representative: StripItem?
        /// **飞行途中可以改终点**（`var` 不是 `let`）。松手那一刻卡槽往往还在跑让位动画，
        /// 量到的是插值中的位置；等它落定再纠一次偏，图标才不会在最后一下跳过去。
        var flight: DragLandingFlight
        /// 已经飞到终点、正在做交接：**条上那张卡这一刻起显形，载体停在原地淡出**。
        /// 两步显式分开，就没有「谁先渲染」的赛跑——见 `DragLandingPlan.handoffFade`。
        var settled = false

        static func == (lhs: Landing, rhs: Landing) -> Bool {
            lhs.token == rhs.token && lhs.flight == rhs.flight && lhs.settled == rhs.settled
        }
    }
    @Published private(set) var landing: Landing?

    /// **视图判「哪一格要空着」一律用它**，不要各自写 `draggingPayload ?? landing?.payload`：
    /// 归位飞行期间原位必须继续空着，否则卡先显形、载体还在飞 = 又是两个影子。
    var carriedPayload: DragPayload? { draggingPayload ?? landing?.payload }

    /// 「手里正拎着东西」（含松手后的归位飞行与交接淡出）。悬停反馈与名字气泡在这期间一律关掉——
    /// 见 `DockStripView.refreshHoveredEntry`。**要一直 true 到载体真的没了**，
    /// 否则卡在淡出途中就长出悬停放大，和还停在上面的载体差出一截。
    var isCarrying: Bool { carriedPayload != nil }

    /// **「这一格要空着」用它，不要用 `carriedPayload`。** 两头都要等对面先画出来：
    ///
    /// - **起拖**：载体真的画出来之前，条上那张卡**不能**先藏。藏早了就是「两边都没有」，
    ///   屏幕上那个图标凭空消失一下——owner 2026-08-18 报「选中一瞬间快速移动鼠标，
    ///   图标会暂时消失」。起拖时载体面板要 order front、SwiftUI 还要走一趟布局，
    ///   比条上改个 opacity 慢，所以这个顺序不能靠运气。
    /// - **落地**：飞行落定之后卡就该显形了（载体停在同一位置淡出，重叠看不出来）；
    ///   继续空着反而会在淡出结束时露出一帧空位。
    ///
    /// 两头都是「先让新的出现，再让旧的消失」，重叠一两帧无害、空档一帧就是可见的闪。
    var hiddenSlotPayload: DragPayload? {
        if draggingPayload != nil { return carrierReady ? draggingPayload : nil }
        guard let landing, !landing.settled else { return nil }
        return landing.payload
    }

    /// 载体这一次拖动已经上屏了吗。**`beginDrag` 里排一个 `main.async` 置位**——
    /// 恰好晚一轮 run loop，也就是恰好晚一帧：这一帧里条上的卡和副本**同时**可见（重叠，
    /// 位置尺寸都一样，看不出来），下一帧卡才藏。
    ///
    /// 上一版用的是 33ms 计时器，反而是 bug 的来源：副本首帧偶尔晚于 33ms，计时器先到就把卡藏了，
    /// 于是两边都没有——owner 连拍的第 4 帧就是这个。现在位置是 AppKit 同步摆好的、
    /// 宿主也预热过，一轮 run loop 足够，不需要猜时间。
    @Published private(set) var carrierReady = false

    /// 拎在手里时的缩放。载体和飞行起点共用这一个表达式——分开写过就会漂。
    var carriedScale: CGFloat {
        isOverDropZone && !isConvertedToStrip ? DragLandingPlan.dropZoneScale : DragLandingPlan.carriedScale
    }

    /// 落点锚点（屏幕坐标）。**两个视图各写各的、每次光标更新都写**，带 owner 标签：
    /// 任务条侧管 `.strip` / `.messaging` 载荷，抽屉侧管 `.drawer` 载荷。
    /// 不owner 标签的话，抽屉图标转正进任务条之后，抽屉那边写下的旧锚点会留着，
    /// 图标就会往已经关掉的抽屉里飞。
    enum LandingAnchorOwner { case strip, drawer }
    private var landingAnchor: (owner: LandingAnchorOwner, rect: CGRect)?
    private var landingTimer: Timer?
    private var carrierReadyFallback: Timer?
    private var landingFadeTimer: Timer?
    private var carrierRenderReported = false
    /// 每次起拖 +1。载体视图拿它做 `.id()`，保证每次拖动都是全新视图、`onAppear` 一定会来。
    @Published private(set) var dragSessionID = 0
    private var dragBeganAt: CFTimeInterval = 0
    private var landingToken = 0
    /// 纠偏可以把飞行往后推，但不能无限推。飞行一开始就定死这个上限。
    private var landingDeadline: CFTimeInterval = 0

    func setLandingAnchor(_ rect: CGRect?, owner: LandingAnchorOwner) {
        if let rect {
            landingAnchor = (owner, rect)
        } else if landingAnchor?.owner == owner {
            landingAnchor = nil
        }
        retargetLandingIfNeeded()
    }

    /// 飞行途中的**中途纠偏**。
    ///
    /// 松手那一刻卡槽多半还在跑让位动画（条内 0.28s 的 spring / 抽屉 0.22s 的网格重排），
    /// `GeometryReader` 报的是插值中的中间值——照它飞过去，等载体撤掉时卡已经落到别处，
    /// 差出来的那十几 pt 就是 owner 看到的「归位还在抖」。锚点在飞行期间会继续更新
    /// （视图那边改成按帧变化上报，见 `updateLandingAnchor`），这里跟着改终点，
    /// SwiftUI 会从当前位置平滑地接上去。
    ///
    /// 门槛 0.5pt：亚像素抖动不值得为它重发一次（`DockStripView` 观察着本对象，
    /// 每发一次都要重算整条 body）。
    private func retargetLandingIfNeeded() {
        guard var current = landing, !current.settled,
              DragLandingPlan.allowsRetarget(
                remainingBeforeDeadline: landingDeadline - CACurrentMediaTime(),
                flightDuration: current.flight.duration),
              let rect = landingAnchor?.rect,
              let updated = DragLandingPlan.flight(from: current.flight.from,
                                                   fromScale: current.flight.fromScale,
                                                   anchorScreenRect: rect,
                                                   carrierScreenFrame: carrierScreenFrame),
              hypot(updated.to.x - current.flight.to.x, updated.to.y - current.flight.to.y) > 0.5
        else { return }
        current.flight = updated
        landing = current
        // 重发一次位移动画：AppKit 会从当前插值位置平滑接到新终点。
        placeCarrier(center: panelPoint(fromTopLeft: updated.to),
                     animated: true, duration: updated.duration)
        // 改了终点就等于重新起飞一段，**计时器必须跟着往后推**——否则载体在半路被撤掉，
        // 那正是要治的那一下跳。上限 `landingDeadline` 保证卡槽万一一直动也不会挂着不放。
        scheduleLandingFinish(token: current.token)
    }

    /// **淡出安排在飞行的最后一小段，而不是落地之后。**
    ///
    /// 原来的做法是「落地 → 卡显形 → 载体再淡出 90ms」，指望两者位置一样所以重叠看不出来。
    /// 实际不是：owner 2026-08-18 的连拍里，落地后那 90ms 能清楚看到一实一虚两个图标上下错开
    /// （载体的最终位置和卡的实际位置差了几个 pt——这个差值我还没查清）。
    /// 改成提前淡：等卡显形的时候载体已经淡到 0 了，**差多少都看不见**。
    private func beginLandingFadeOut(token: Int, flightDuration: TimeInterval) {
        let lead = max(0, flightDuration - DragLandingPlan.handoffFade)
        let timer = Timer(timeInterval: lead, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.landing?.token == token, let panel = self.carrierPanel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = DragLandingPlan.handoffFade
                    panel.animator().alphaValue = 0
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        landingFadeTimer = timer
    }

    /// 飞到终点：载体此刻已经淡到 0，直接收掉并让条上那张卡显形。幂等。
    func finishLanding() {
        landingTimer?.invalidate(); landingTimer = nil
        guard var current = landing, !current.settled else { return }
        current.settled = true
        landing = current
        abortLanding()
    }

    /// 立刻结束飞行、不做交接（新拖动打断、异常取消、面板拆除）。
    func abortLanding() {
        landingTimer?.invalidate(); landingTimer = nil
        landingFadeTimer?.invalidate(); landingFadeTimer = nil
        guard landing != nil else { return }
        landing = nil
        carrierPanel?.orderOut(nil)
        carrierPanel?.alphaValue = 1       // 下次起拖必须是不透明的
    }

    /// 胶囊高亮只在「任务条卡/消息 chip 正悬在收纳区」时亮；任务条移回高亮只在「抽屉图标正悬在任务条」时亮。
    var isOverStashZone: Bool {
        guard isOverDropZone, let s = draggingPayload?.source else { return false }
        return s == .strip || s == .messaging
    }
    var isOverUnstashZone: Bool { isOverDropZone && draggingPayload?.source == .drawer }

    /// 跨面板**临时转换**状态——显式"原始来源 + 回滚快照"，同一时刻至多一个转换在进行
    /// （Codex 评审 2026-07-11：不再叠布尔标志）。commit = `teardown()` 清状态不回滚；
    /// rollback = 各 revert 方法按快照还原；`cancelDrag()` 按当前 case 回滚后收尾。
    /// `@Published`：载体切换、任务条宽度冻结、成员监听豁免都要能驱动刷新。
    enum CrossPanelConversion {
        /// 任务条卡已临时收进抽屉。回滚 = drawer.remove + 还原载荷；kept 不变。
        case stripToDrawer(original: DragPayload)
        /// 抽屉图标已临时转正进任务条（unstash / keepPlacement）。回滚 = drawer.add。
        case drawerToStrip(bundleID: String)
        /// 消息区 chip 已临时收进抽屉。回滚 = drawer.remove + 还原 `.messaging` 载荷。
        case messagingToDrawer(original: DragPayload)
        /// 抽屉里运行中的消息应用已临时释放回消息区。回滚 = drawer.add + 还原 `.drawer` 载荷。
        case drawerToMessaging(original: DragPayload)
    }
    @Published private(set) var conversion: CrossPanelConversion?

    /// 兼容视图层现有调用点的投影（读 `conversion`，@Published 保证驱动刷新）。
    var convertedDrawerBundleID: String? {
        if case let .drawerToStrip(bid) = conversion { return bid }
        return nil
    }
    var isConvertedToStrip: Bool { convertedDrawerBundleID != nil }
    var isConvertedFromStrip: Bool {
        if case .stripToDrawer = conversion { return true }
        return false
    }
    var isConvertedFromMessaging: Bool {
        if case .messagingToDrawer = conversion { return true }
        return false
    }
    var isReleasedToMessaging: Bool {
        if case .drawerToMessaging = conversion { return true }
        return false
    }

    /// 转正后载体改画的**唯一代表卡**。由 DockStripView 在窗口卡实体化后写入（显示序里该 app 第一张
    /// 已实体化的**真窗口卡**），未实体化前为 nil（载体仍画抽屉小图标）。`revert`/`teardown` 清空。
    @Published private(set) var convertedRepresentative: StripItem?

    /// 转正后**条上要隐藏哪张卡**（让出空位）。和上面那个刻意分开成两个字段：
    ///
    /// 载体只能画 `StripItem`，而条上物化出来的可能是 `.keptApp` 占位或 `isAppLevelFallback`
    /// 的兜底卡——两者都不是"能画成一张窗口卡"的东西，`liveChipIDs` 也把它们排除在外。
    /// 早先两件事共用 `convertedRepresentative` 一个字段，于是 `keepPlacement` 路径
    /// （未运行的保留应用、只有 app 级兜底卡的运行应用）它永远是 nil，**条上那张卡全不透明地
    /// 画着、手里还拎着同一个图标 = 两个影子**（owner 2026-08-18 报）。
    /// 所以这里存的是 chip id，不是卡本身。
    @Published private(set) var convertedChipID: String?

    func setConvertedRepresentative(_ item: StripItem?, chipID: String?) {
        if convertedRepresentative != item { convertedRepresentative = item }
        if convertedChipID != chipID {
            convertedChipID = chipID
            HoverTrace.carrierRepresentative(rep: item?.id, hidden: chipID)
        }
    }
    /// 成功松手落定（converted 态）时回调，组合层接到后 `stripOrderStore.commitExternalBlock()`。
    /// 唯一收到 mouseUp 的是 `endDrag`，commit 必须由它触发，不靠 DockStripView 推断 payload 变 nil。
    var onDrawerToStripCommitted: ((String) -> Void)?
    /// 抽屉拖回任务条·异常取消（cancelDrag）时回调，组合层接到后 `stripOrderStore.cancelExternalBlock()`。
    /// 与 onDrawerToStripCommitted 对称：commit = 落定清暂存；cancel = 撤销清暂存+boundIDs。
    var onDrawerToStripCancelled: (() -> Void)?
    /// 抽屉图标松手落进任务条时回调（精确落点路径 + 降级路径都会触发）。
    /// PanelCoordinator 用它关闭抽屉；与 onDrawerToStripCommitted 独立，互不替代。
    var onDrawerToStripCompleted: ((String) -> Void)?
    /// 文件夹 chip 拖动的实时落点分类——**DockStripView 算好写入**（它才有 folderChipFrames/
    /// shelfFrame/stripRootScreenRect），载体视图（DragCarrierView）只读它决定要不要淡出。
    /// 最终 mouseUp 仍由 `endDrag()` 触发，并用 `folderDropGeometry` 重新分类一次。
    @Published private(set) var folderDragZone: FolderChipDropZone?
    func setFolderDragZone(_ zone: FolderChipDropZone?) {
        if folderDragZone != zone { folderDragZone = zone }
    }
    private var folderDropGeometry: FolderChipDropGeometry?
    func setFolderDropGeometry(_ geometry: FolderChipDropGeometry?) {
        if folderDropGeometry != geometry { folderDropGeometry = geometry }
    }
    /// 固定文件夹拖拽松手落定。PanelCoordinator 执行 store / Finder 副作用；controller 只负责可靠收尾。
    var onFolderDragEnded: ((String, FolderChipDropZone) -> Void)?

    /// 本次拖动的**原始来源**。转换会翻 `draggingPayload.source`（进抽屉体后变 `.drawer`），
    /// 所以判「这次拖动是不是把它从抽屉外带进来的」只能看这个。唯一权威是 `conversion` 里的
    /// 回滚快照——**不另设并行字段**（见 `CrossPanelConversion` 的注释：不再叠布尔标志）。
    private var originSource: DragSource? {
        guard let payload = draggingPayload else { return nil }
        switch conversion {
        case let .stripToDrawer(original),
             let .messagingToDrawer(original),
             let .drawerToMessaging(original):
            return original.source
        case .drawerToStrip:
            return .drawer
        case nil:
            return payload.source
        }
    }

    private let drawerStore: DrawerStore
    private let messagingStore: MessagingAppStore
    private let keptAppStore: KeptAppStore
    /// 按来源给投放候选区（屏幕坐标，已 inset+容错）：strip/messaging→胶囊(+抽屉)；drawer→任务条 dock 面板。
    private let dropZonesProvider: (DragSource) -> [CGRect]
    private let screenProvider: () -> NSScreen
    private let carrierFactory: (DragController) -> NSView

    private var carrierPanel: NSPanel?
    /// 副本那块小 hosting 视图。**位置就是它的 frame**，由 `placeCarrier` 直接设。
    private var carrierHost: NSView?
    private weak var carrierContainer: CarrierContainerView?

    /// 副本的 SwiftUI 内容**真的构建出来了**——由 `DragCarrierView` 在内容 `onAppear` 里回报。
    ///
    /// 条上那格要等这一声、**再多等一轮 run loop**（让这一帧真的提交）才允许空出来。
    /// 宁可两边重叠一两帧（位置尺寸一样，看不出来），也绝不能出现两边都没有的空档。
    ///
    /// 走过的两条弯路，都记在这儿免得再来一遍：
    /// - `CarrierContainerView.viewWillDraw` 收不到：`NSHostingView` 走 CoreAnimation 图层，
    ///   不经过视图的绘制路径（实测 5 次全部落到兜底计时器上）。
    /// - **`layoutSubtreeIfNeeded()` + `displayIfNeeded()` 逼不出来**：那两个逼的是 AppKit 的
    ///   布局与绘制，而此刻载荷刚发布、SwiftUI 那次更新还没处理，逼出来的是**上一帧的空内容**。
    ///   照着它当场放行，几乎每次拖动都会露出空档（owner 2026-08-18：「几乎每次都消失」）。
    ///   SwiftUI 自己什么时候画好，只有它自己知道——所以只能听它的 `onAppear`。
    func markCarrierRendered() {
        guard draggingPayload != nil, !carrierReady, !carrierRenderReported else { return }
        carrierRenderReported = true
        HoverTrace.dragHandoff("carrierRendered", msSinceBegin: (CACurrentMediaTime() - dragBeganAt) * 1000)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.draggingPayload != nil, !self.carrierReady else { return }
            self.carrierReady = true
            HoverTrace.dragHandoff("slotHidden", msSinceBegin: (CACurrentMediaTime() - self.dragBeganAt) * 1000)
        }
    }

    /// 兜底：万一那一声始终没来，也不能让条上一直留着卡（那就成了"原地和手里各一个"）。
    /// 给得比实测宽裕得多——宁可晚藏，不可早藏。
    private func armCarrierReadyFallback() {
        let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.draggingPayload != nil, !self.carrierReady else { return }
                self.carrierReady = true
                HoverTrace.dragHandoff("slotHiddenByFallback",
                                       msSinceBegin: (CACurrentMediaTime() - self.dragBeganAt) * 1000)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        carrierReadyFallback = timer
    }
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pollTimer: Timer?

    init(drawerStore: DrawerStore,
         messagingStore: MessagingAppStore,
         keptAppStore: KeptAppStore,
         dropZonesProvider: @escaping (DragSource) -> [CGRect],
         screenProvider: @escaping () -> NSScreen,
         carrierFactory: @escaping (DragController) -> NSView) {
        self.pointerMoves = pointerSubject.eraseToAnyPublisher()
        self.drawerStore = drawerStore
        self.messagingStore = messagingStore
        self.keptAppStore = keptAppStore
        self.dropZonesProvider = dropZonesProvider
        self.screenProvider = screenProvider
        self.carrierFactory = carrierFactory
    }

    // MARK: - 起拖

    func beginDrag(payload: DragPayload, startScreenLocation: CGPoint, grabOffset: CGSize) {
        guard draggingPayload == nil else { return }
        // 上一次的归位还在飞就立刻收掉（**不走交接淡出**：那是给正常落地用的）。
        abortLanding()
        let started = CACurrentMediaTime()
        dragBeganAt = started
        let hadCarrier = carrierPanel != nil
        carrierReady = false
        carrierRenderReported = false
        dragSessionID &+= 1
        self.grabOffset = grabOffset
        globalLocation = startScreenLocation
        pointerSubject.send(startScreenLocation)
        // **先把载体摆到位、再发布载荷**：宿主视图的 frame 是同步设的，所以 SwiftUI 一画出内容
        // 就已经在正确的位置上，不会先出现在别处再跳过去。
        let beforeCarrier = CACurrentMediaTime()
        showCarrier()
        let afterCarrier = CACurrentMediaTime()
        draggingPayload = payload
        refreshDropZone()
        installMonitors()
        startPoll()
        armCarrierReadyFallback()
        HoverTrace.dragStart(totalMs: (CACurrentMediaTime() - started) * 1000,
                             carrierMs: (afterCarrier - beforeCarrier) * 1000,
                             carrierCreated: !hadCarrier)
    }

    // MARK: - 任务条卡进抽屉体 → 转成抽屉内拖动（统一手感，owner 2026-06-22）

    /// 任务条卡拖进**打开的抽屉体** → 即时"转正"成抽屉成员、把来源改成 `.drawer`。之后完全走抽屉内
    /// 重排路径（全局鼠标驱动、无占位空格、无面板反复缩放）——彻底绕开旧的"占位+面板缩放"机制。
    /// **可逆**：转正只是临时插入(挤开别人=预览);卡拖出抽屉体 → `revertStripFromDrawer` 撤销还原;
    /// 真正松手落在抽屉里那刻才算落定（owner 2026-06-22：再开抽屉要是最初的样子,不是被挤过的）。
    /// `guard source==.strip && conversion==nil` 保证幂等（转一次后不再触发）。
    func convertStripToDrawer() {
        guard let p = draggingPayload, p.source == .strip, p.canExternalDrop, conversion == nil else { return }
        conversion = .stripToDrawer(original: p)  // 先置（同步触发宽度冻结），再动 store
        draggingPayload = DragPayload(source: .drawer, id: p.bundleID, bundleID: p.bundleID,
                                      item: p.item, visualKind: p.visualKind, canExternalDrop: true)
        drawerStore.add(p.bundleID)
        refreshDropZone()   // 投放区集合随来源变,重算
    }

    /// 撤销转正：卡拖出抽屉体 → 从抽屉成员里移除（抽屉缩回原样、其他图标归位）、来源还原成任务条卡。
    /// 之后再次拖进抽屉体会重新 `convertStripToDrawer`。让"再开抽屉=最初的样子"。
    /// 先清转换态、先还原载荷，**再**动 store——成员监听按新载荷来源豁免，无取消竞态（评审 P1-2）。
    func revertStripFromDrawer() {
        guard case let .stripToDrawer(original) = conversion, draggingPayload?.source == .drawer else { return }
        conversion = nil    // 解冻 + 触发 relayout（拖出抽屉还原 → 任务条恢复原宽）
        draggingPayload = original
        drawerStore.remove(original.bundleID)
        refreshDropZone()
    }

    // MARK: - 消息区 chip 进抽屉体 → 收纳预览 / 拖出还原（与任务条卡同一套手感）

    /// 消息区 chip 拖进**打开的抽屉体** → 临时收纳成抽屉成员、来源翻成 `.drawer`（此后抽屉内重排
    /// 全套复用）。**不动消息 flag**——收进抽屉只是投影隐藏，与既有收纳语义一致。
    /// 先置转换态、先翻载荷再 `drawer.add`：消息区监听按来源豁免，不误判"chip 从区里消失"（评审 P1-2/P2-5）。
    func convertMessagingToDrawer() {
        guard let p = draggingPayload, p.source == .messaging, p.canExternalDrop, conversion == nil else { return }
        conversion = .messagingToDrawer(original: p)
        draggingPayload = DragPayload(source: .drawer, id: p.bundleID, bundleID: p.bundleID,
                                      item: nil, visualKind: .drawerIcon, canExternalDrop: true)
        drawerStore.add(p.bundleID)
        refreshDropZone()
    }

    /// 撤销收纳预览：拖出抽屉体 → 移出抽屉成员、载荷还原 `.messaging`（chip 回消息区原位）。
    func revertMessagingFromDrawer() {
        guard case let .messagingToDrawer(original) = conversion, draggingPayload?.source == .drawer else { return }
        conversion = nil
        draggingPayload = original
        drawerStore.remove(original.bundleID)
        refreshDropZone()
    }

    // MARK: - 抽屉图标拖进任务条区 → 转正成任务条窗口卡 / 拖出还原（抽屉拖回任务条·精确落点，2026-06-22）

    /// 抽屉图标拖进**任务条面板区** → 即时"转正"：`drawerStore.remove(bid)`，该 app 的窗口卡随即进 live 区。
    /// 落点排序（暂存 + sync 内落子）归 DockStripView，本方法只管成员变更 + 记 bundleID。**不翻 source**——保
    /// `.drawer` 让 `isOverUnstashZone` 高亮与 `endDrag` 的 `.drawer` 分支继续成立。`guard` 保幂等。
    func convertDrawerToStrip() {
        guard let p = draggingPayload, p.source == .drawer, p.canExternalDrop, conversion == nil else { return }
        conversion = .drawerToStrip(bundleID: p.bundleID)  // 先置（宽度冻结），再动 drawerStore
        drawerStore.remove(p.bundleID)
    }

    /// 撤销转正：拖出任务条区 → `drawerStore.add(bid)` 还原 placement；kept 始终不变。
    /// 顺序层的撤销（删 boundIDs + 清 absentSince）由 DockStripView 在调本方法**之前** `cancelExternalBlock`。
    func revertDrawerToStrip() {
        guard case let .drawerToStrip(bid) = conversion else { return }
        drawerStore.add(bid)
        conversion = nil
        convertedRepresentative = nil   // 载体恢复抽屉小图标
        convertedChipID = nil           // 条上不再有卡需要让位
    }

    // MARK: - 抽屉里的消息应用拖进消息区范围 → 临时释放回消息区 / 离区还原（评审 P1-3）

    /// 抽屉起拖的**运行中消息应用**进入消息区范围 → 临时释放：载荷翻成 `.messaging`（区内重排、
    /// 再进抽屉的收纳预览全部复用通用逻辑），再 `drawer.remove`（投影立即让 chip 回到消息区原顺序位）。
    /// 触发范围由 DockStripView 按消息区帧判定——**不是**"离开抽屉体就释放"。
    func convertDrawerToMessaging() {
        guard let p = draggingPayload, p.source == .drawer, p.canExternalDrop, conversion == nil else { return }
        conversion = .drawerToMessaging(original: p)
        draggingPayload = DragPayload(source: .messaging, id: p.bundleID, bundleID: p.bundleID,
                                      item: nil, visualKind: .messagingIcon, canExternalDrop: true)
        drawerStore.remove(p.bundleID)
        refreshDropZone()
    }

    /// 撤销释放：离开消息区范围（或进投放区）→ 收回抽屉、载荷还原 `.drawer`。
    func revertDrawerToMessaging() {
        guard case let .drawerToMessaging(original) = conversion, draggingPayload?.source == .messaging else { return }
        conversion = nil
        draggingPayload = original
        drawerStore.add(original.bundleID)
        refreshDropZone()
    }

    // MARK: - 跟手 / 落点

    private func update(_ loc: CGPoint) {
        globalLocation = loc
        // **同步摆位，第一件事就做**：这是跟手性的全部。走 SwiftUI 的老路子每帧要过一遍渲染管线，
        // 拖快了副本会落在光标后面一百多 pt（owner 2026-08-18 连拍实证）。
        placeCarrier(center: carrierCenterInPanel())
        refreshDropZone()
        pointerSubject.send(loc)    // 副作用订阅方（条 / 抽屉），不建立视图依赖
        auditCarrierVisibility()
        auditCarrierDouble()
    }

    /// 反向自检：**副本已经在屏幕上了，条上那格却还占着** = 同一个图标画了两份（重影）。
    /// owner 2026-08-18 的连拍里这是最显眼的一条，靠肉眼分不清是重影还是动态模糊，这里直接记事实。
    private func auditCarrierDouble() {
        guard HoverTrace.isEnabled, draggingPayload != nil, !carrierReady,
              let panel = carrierPanel, panel.isVisible, panel.alphaValue > 0.99,
              carrierRenderReported else { return }
        HoverTrace.carrierGap(reason: "doubleImage", alpha: panel.alphaValue,
                              hostX: carrierHost?.frame.minX ?? -1,
                              hostY: carrierHost?.frame.minY ?? -1)
    }

    /// 每次光标更新自检一次：**条上那格已经空了，副本是不是真的在屏幕上？**
    /// 两者只要不同时成立，用户看到的就是「图标不见了」。owner 连着三轮报「偶尔会消失」，
    /// 靠截图只能猜；这条把它变成日志里可以数的事实。
    private func auditCarrierVisibility() {
        guard HoverTrace.isEnabled, let payload = hiddenSlotPayload,
              let panel = carrierPanel, let host = carrierHost else { return }
        let onScreen = panel.isVisible && panel.alphaValue > 0.99
        // 图标中心（不是宿主整块）必须真的落在屏幕内：宿主 360×200 比图标大得多，
        // 只判 `intersects` 会把「图标已经出屏、宿主边角还压着」当成正常。
        let iconOnScreen = CGRect(origin: .zero, size: carrierScreenFrame.size)
            .insetBy(dx: -24, dy: -24).contains(CGPoint(x: host.frame.midX, y: host.frame.midY))
        // `.stripChip` 却没带 `item` → `DragCarrierView.content` 什么都不画，副本是空的。
        let drawable = payload.visualKind != .stripChip || payload.item != nil
            || convertedRepresentative != nil
        guard !onScreen || !iconOnScreen || !drawable else { return }
        let reason = !panel.isVisible ? "panelHidden"
            : (panel.alphaValue <= 0.99 ? "panelFaded"
               : (!drawable ? "emptyContent" : "iconOffscreen"))
        _ = payload
        HoverTrace.carrierGap(reason: reason, alpha: panel.alphaValue,
                              hostX: host.frame.minX, hostY: host.frame.minY)
    }

    /// **只在结论真的变了才写**：`@Published` 是每次赋值都发通知，不比较旧值。
    /// 每动一下鼠标写一次，就等于每动一下鼠标打翻一次整条任务条（同 `globalLocation` 那条）。
    private func refreshDropZone() {
        let next: Bool = {
            guard let p = draggingPayload, p.canExternalDrop else { return false }
            return dropZonesProvider(p.source).contains { $0.contains(globalLocation) }
        }()
        if isOverDropZone != next { isOverDropZone = next }
    }

    // MARK: - 收尾（幂等，先清后提交）

    /// 正常松手：在投放区 → 按来源收纳/移回；否则什么都不做（区内排序已在拖动中实时提交）。
    /// `.messaging`/`.drawer` 的收尾决策走纯逻辑 `DragConversionPlan.endAction`（单测覆盖）。
    func endDrag() {
        guard let p = draggingPayload else { return }
        let external = isOverDropZone
        let converted = isConvertedToStrip
        let convertedBid = convertedDrawerBundleID
        let origin = originSource ?? p.source   // 必须赶在 teardown() 清 conversion 之前取
        let finalLocation = globalLocation
        let folderZone = folderDropGeometry?.classify(screenPoint: finalLocation) ?? .folderZone
        let action = DragConversionPlan.endAction(source: p.source,
                                                  isConvertedToStrip: converted,
                                                  isOverDropZone: external,
                                                  isMessagingMember: messagingStore.contains(p.bundleID))
        teardown(landing: plannedLanding(for: p))
        switch p.source {
        case .folder:
            onFolderDragEnded?(p.id, folderZone)
        case .strip:
            // 进过抽屉体的卡已被 convertStripToDrawer 转成 .drawer（落在里面 = 已是成员、不走这里）。
            // 走到这支 = 没进抽屉体的卡：在投放区(胶囊)松手 → 改 drawer placement。
            // kept 不在这里动——四条入口共用 switch 之后那段统一判据。
            if external {
                drawerStore.add(p.bundleID)
            }
        case .messaging:
            // 消息区起拖未转换（转换后来源已是 .drawer），或抽屉起拖已释放回消息区（drawer.remove
            // 已发生，松手即落定）。投放区（胶囊）→ 收纳；其余任意位置 → 原地不动（区内重排已实时提交）。
            if action == .stashMessagingChip {
                drawerStore.add(p.bundleID)
            }
        case .drawer:
            switch action {
            case .commitDrawerToStrip:
                // 已转正进任务条（成员已 remove、窗口卡已落子）→ 视为落定，不再据 external 动成员。
                // 撤销已在实时离区时发生；这里只通知顺序层 commit（清暂存追踪）。
                let bid = convertedBid ?? p.bundleID
                onDrawerToStripCommitted?(bid)
                onDrawerToStripCompleted?(bid)
            case .fallbackUnstash:
                // 没转正（没运行 / app-fallback）：落任务条 → 移回。消息成员永不走这支——
                // 它回任务条的唯一路径是消息区范围的临时释放（评审 P1-3），其他位置松手留在抽屉。
                drawerStore.remove(p.bundleID)
                onDrawerToStripCompleted?(p.bundleID)
            case .none, .stashMessagingChip:
                break
            }
        }

        // 收纳落定 → 打开「在程序坞中保留」（owner 2026-08-06）。放在 switch **之后**：
        // 此刻 drawerStore 已是最终成员关系，四条入口路径（任务条/消息 chip × 抽屉体/胶囊）
        // 共用一个判据，也天然排除了抽屉内重排、转正进任务条、降级移出这些不该开启的情形。
        // 语义（只进不出、每次拖入都重新打开）见 DragConversionPlan.enablesKeptOnDrop。
        if DragConversionPlan.enablesKeptOnDrop(originSource: origin,
                                                endedInDrawer: drawerStore.contains(p.bundleID)) {
            keptAppStore.add(p.bundleID)
        }
    }

    /// 取消：拖动中目标消失、切屏等异常路径。先按当前转换态回滚已发生的 store 变更
    /// （与各"拖出还原"同路径），再收尾——每个临时态都恢复原成员关系。
    func cancelDrag() {
        // 归位飞行期间 `draggingPayload` 已经是 nil，但载体面板还开着——切屏 / 面板拆除
        // 这些路径都走这里，不先收掉的话会把一个半透明的全屏载体留在屏幕上。
        abortLanding()
        guard draggingPayload != nil else { return }
        switch conversion {
        case .stripToDrawer:
            revertStripFromDrawer()
        case .drawerToStrip:
            onDrawerToStripCancelled?()
            revertDrawerToStrip()
        case .messagingToDrawer:
            revertMessagingFromDrawer()
        case .drawerToMessaging:
            revertDrawerToMessaging()
        case nil:
            break
        }
        // 异常取消（目标消失/切屏）不飞：那不是"落到某一格"，飞回一个已经不存在的位置只会更怪。
        teardown(landing: nil)
    }

    /// 这次松手该不该飞、飞到哪。拿不到落点锚点（或被 `DOCK_DRAG_LANDING=0` 关掉）→ nil → 瞬时收尾。
    private func plannedLanding(for payload: DragPayload) -> Landing? {
        guard DragLandingSwitches.enabled else { return nil }
        let from = carrierPosition()
        let flight = DragLandingPlan.flight(from: from,
                                            fromScale: carriedScale,
                                            anchorScreenRect: landingAnchor?.rect,
                                            carrierScreenFrame: carrierScreenFrame)
        HoverTrace.landing(from: from, to: flight?.to, source: "\(payload.source)")
        guard let flight else { return nil }
        landingToken &+= 1
        return Landing(token: landingToken, payload: payload,
                       representative: convertedRepresentative, flight: flight)
    }

    /// 收尾。`landing` 非空时**不收载体面板**——它还要飞 0.26 秒；到点由 `finishLanding()` 收。
    private func teardown(landing flight: Landing?) {
        conversion = nil                  // 落定路径：清转换态不回滚（commit）；解冻任务条宽度
        convertedRepresentative = nil
        convertedChipID = nil
        folderDragZone = nil
        folderDropGeometry = nil
        draggingPayload = nil
        isOverDropZone = false
        landingAnchor = nil
        carrierReady = false
        carrierRenderReported = false
        carrierReadyFallback?.invalidate(); carrierReadyFallback = nil
        removeMonitors()
        pollTimer?.invalidate(); pollTimer = nil
        landingTimer?.invalidate(); landingTimer = nil
        landing = flight
        guard let flight else { carrierPanel?.orderOut(nil); return }
        landingDeadline = CACurrentMediaTime() + DragLandingPlan.maximumDuration
        // 位移交给 AppKit（缩放仍在 SwiftUI，两边同一条曲线同一个时长）。
        placeCarrier(center: panelPoint(fromTopLeft: flight.flight.to),
                     animated: true, duration: flight.flight.duration)
        beginLandingFadeOut(token: flight.token, flightDuration: flight.flight.duration)
        scheduleLandingFinish(token: flight.token)
    }

    /// 排（或重排）「飞完了就收载体」那一下。
    /// `.common`：松手瞬间主 run loop 可能还在事件跟踪模式，default 模式的计时器不会触发，
    /// 载体就会永远停在半空（同 `armSpringOpenTimer` 的理由）。
    private func scheduleLandingFinish(token: Int) {
        landingTimer?.invalidate()
        let flightDuration = landing?.flight.duration ?? DragLandingPlan.duration
        let remaining = max(0.05, min(flightDuration + DragLandingPlan.settleMargin,
                                      landingDeadline - CACurrentMediaTime()))
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.landing?.token == token else { return }
                self.finishLanding()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        landingTimer = timer
    }

    /// 任务条卡能否收纳：只拦无 bundleID 与 Finder（Finder 永远保留任务条入口）。
    /// 不拦 app-level fallback —— 抽屉运行区本就显示应用级图标。
    static func canStash(_ item: StripItem) -> Bool {
        guard let bid = item.bundleIdentifier, !bid.isEmpty else { return false }
        if bid == "com.apple.finder" { return false }
        return true
    }

    // MARK: - 载体面板

    /// 提前把载体面板和它那棵 SwiftUI 宿主树建好，别让用户的**第一次拖动**替我们付这笔钱。
    ///
    /// 实测（`DOCK_HOVER_TRACE`，2026-08-18）：会话里第一次起拖 `showCarrier()` 要 **20.3ms**，
    /// 同时主线程有一次 **38.9ms** 的卡顿——60Hz 下就是丢掉两三帧，正是 owner 说的
    /// 「选中图标拖动的第一帧有卡顿」。之后每次只要 5.9ms。
    ///
    /// 得**真的 order front 一次**才算数：`NSHostingView` 不在可见窗口里不会走布局，
    /// 光 `contentView = host` 只建了对象，SwiftUI 那一趟还是留给第一次拖动。
    /// alpha 归零 + `ignoresMouseEvents`，这一瞬间屏幕上什么都看不到。
    func prewarmCarrier() {
        guard carrierPanel == nil else { return }
        let panel = makeCarrierPanel()
        panel.setFrame(screenProvider().frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
        carrierPanel = panel
    }

    private func showCarrier() {
        let screen = screenProvider()
        carrierScreenFrame = screen.frame
        let panel = carrierPanel ?? makeCarrierPanel()
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = 1               // 上一次交接淡出可能把它留在半透明
        placeCarrier(center: carrierCenterInPanel())
        panel.orderFrontRegardless()
        carrierPanel = panel
    }

    /// 把副本摆到面板内的某个中心点（AppKit 坐标，左下原点）。
    ///
    /// - `animated: false`（跟手那条路）**必须关掉隐式动画**：CALayer 的 position 默认带 0.25s 的
    ///   隐式动画，不关的话每一帧都在往上一帧的目标插值，副本会永远软绵绵地落在光标后面。
    /// - `animated: true` 只给归位飞行用，曲线与时长和 SwiftUI 那边的缩放**取同一份**
    ///   （`DragLandingPlan.curve` / `flight.duration`），两者才像一次运动。
    private func placeCarrier(center: CGPoint, animated: Bool = false, duration: TimeInterval = 0) {
        guard let host = carrierHost else { return }
        let size = host.frame.size
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            host.setFrameOrigin(origin)
            CATransaction.commit()
            if HoverTrace.isEnabled {
                let immediate = host.frame.origin
                DispatchQueue.main.async { [weak host] in
                    guard let host else { return }
                    HoverTrace.carrierPlacement(wanted: origin, immediate: immediate,
                                                deferred: host.frame.origin,
                                                size: host.frame.size,
                                                autolayout: !host.translatesAutoresizingMaskIntoConstraints)
                }
            }
            return
        }
        let c = DragLandingPlan.curve
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(c.c0x), Float(c.c0y), Float(c.c1x), Float(c.c1y))
            context.allowsImplicitAnimation = true
            host.animator().setFrameOrigin(origin)
        }
    }

    /// 屏幕坐标 → 载体面板内 **AppKit** 坐标（左下原点）的副本中心。
    /// `grabOffset` 是在 `"strip"` / `"drawer"` 那种 y 向下的空间里量的，所以纵向要反号。
    private func carrierCenterInPanel() -> CGPoint {
        CGPoint(x: globalLocation.x - carrierScreenFrame.minX + grabOffset.width,
                y: globalLocation.y - carrierScreenFrame.minY - grabOffset.height)
    }

    /// `DragLandingPlan` 算出来的终点是 y 向下的面板内坐标，翻成 AppKit 的左下原点。
    private func panelPoint(fromTopLeft point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: carrierScreenFrame.height - point.y)
    }

    private func makeCarrierPanel() -> NSPanel {
        // NonConstrainingPanel: 载体覆盖整屏，若被系统约束到"当前屏"可用区会错位（多屏共享边场景），同 dock/胶囊。
        let panel = NonConstrainingPanel(contentRect: screenProvider().frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu                 // 压在抽屉(.floating)之上
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 1.0, alpha: 0.0)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true          // 纯绘制，绝不抢事件
        let host = carrierFactory(self)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor
        host.frame = CGRect(origin: .zero, size: DragLandingPlan.carrierHostSize)
        // 面板的 contentView 是一块**普通全屏 NSView**，副本那块小 hosting 视图挂在里面。
        // 这样既满足 AGENTS「面板不得拿 hosting 当 contentView」那条护栏（原来这里是那条规则的
        // 第 4 处暴露点），又让「摆位置」变成改一个子视图的 frame —— 摆位从此不经过 SwiftUI。
        let container = CarrierContainerView(frame: screenProvider().frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor
        container.autoresizingMask = [.width, .height]
        container.addSubview(host)
        carrierContainer = container
        panel.contentView = container
        carrierHost = host
        return panel
    }

    /// 弹簧开抽屉后把载体重新提到最前——新开的抽屉 orderFront 后可能盖住先于它创建的载体（owner 2026-06-21
    /// 报告"拖进弹簧开的抽屉时浮动图标消失"）。仅拖动进行中才动。
    func bringCarrierToFront() {
        guard draggingPayload != nil, let c = carrierPanel else { return }
        c.orderFrontRegardless()
    }

    /// 屏幕坐标(bottom-left) → 载体面板内 y 向下的卡片中心位置。
    /// **只剩 `DragLandingPlan.flight` 的起点在用它**（那套判定用的是 y 向下的坐标系）；
    /// 实际摆位走 `carrierCenterInPanel()` + `placeCarrier`。
    private func carrierPosition() -> CGPoint {
        CGPoint(x: globalLocation.x - carrierScreenFrame.minX + grabOffset.width,
                y: carrierScreenFrame.maxY - globalLocation.y + grabOffset.height)
    }

    // MARK: - 监视器 + 轮询兜底

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] ev in
            guard let self else { return ev }
            let loc = NSEvent.mouseLocation
            if ev.type == .leftMouseUp { self.update(loc); self.endDrag() }
            else { self.update(loc) }
            return ev
        }
        // global 实测全程 0 次（隐式抓取锁给本 app），留作廉价兜底。
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] ev in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            if ev.type == .leftMouseUp { self.update(loc); self.endDrag() }
            else { self.update(loc) }
        }
    }

    private func removeMonitors() {
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    private func startPoll() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.draggingPayload != nil else { return }
                if NSEvent.pressedMouseButtons == 0 { self.endDrag() }
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}

// 载体视图（DragCarrierView / DrawerDragIconView）在 App/Composition/DragCarrierView.swift——
// 它牵 ChipView/PinnedFolderChip 等 UI 依赖,拆出去让本控制器可被测试 target 本地编译。

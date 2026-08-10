import AppKit
import SwiftUI

// `DragSource` 定义在 Core/Support/DragConversionPlan.swift（纯决策层，测试 target 本地编译）。

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
    @Published private(set) var globalLocation: CGPoint = .zero
    @Published private(set) var isOverDropZone = false

    private(set) var grabOffset: CGSize = .zero
    private(set) var carrierScreenFrame: CGRect = .zero

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

    /// 转正后载体改画的**唯一代表卡**：载体（画哪张卡）与任务条空位（隐藏哪张卡）都认它，避免"手里拎 A、
    /// 条里空出 B"（Codex 三审 P1）。由 DockStripView 在窗口卡实体化后写入（显示序里该 app 第一张已实体化的
    /// 卡），未实体化前为 nil（载体仍画抽屉小图标）。`revert`/`teardown` 清空。
    @Published private(set) var convertedRepresentative: StripItem?
    func setConvertedRepresentative(_ item: StripItem?) {
        if convertedRepresentative != item { convertedRepresentative = item }
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
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var pollTimer: Timer?

    init(drawerStore: DrawerStore,
         messagingStore: MessagingAppStore,
         keptAppStore: KeptAppStore,
         dropZonesProvider: @escaping (DragSource) -> [CGRect],
         screenProvider: @escaping () -> NSScreen,
         carrierFactory: @escaping (DragController) -> NSView) {
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
        self.grabOffset = grabOffset
        globalLocation = startScreenLocation
        draggingPayload = payload
        refreshDropZone()
        showCarrier()
        installMonitors()
        startPoll()
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
        refreshDropZone()
    }

    private func refreshDropZone() {
        guard let p = draggingPayload, p.canExternalDrop else { isOverDropZone = false; return }
        isOverDropZone = dropZonesProvider(p.source).contains { $0.contains(globalLocation) }
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
        teardown()
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
        teardown()
    }

    private func teardown() {
        conversion = nil                  // 落定路径：清转换态不回滚（commit）；解冻任务条宽度
        convertedRepresentative = nil
        folderDragZone = nil
        folderDropGeometry = nil
        draggingPayload = nil
        isOverDropZone = false
        removeMonitors()
        pollTimer?.invalidate(); pollTimer = nil
        carrierPanel?.orderOut(nil)
    }

    /// 任务条卡能否收纳：只拦无 bundleID 与 Finder（Finder 永远保留任务条入口）。
    /// 不拦 app-level fallback —— 抽屉运行区本就显示应用级图标。
    static func canStash(_ item: StripItem) -> Bool {
        guard let bid = item.bundleIdentifier, !bid.isEmpty else { return false }
        if bid == "com.apple.finder" { return false }
        return true
    }

    // MARK: - 载体面板

    private func showCarrier() {
        let screen = screenProvider()
        carrierScreenFrame = screen.frame
        let panel = carrierPanel ?? makeCarrierPanel()
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        carrierPanel = panel
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
        // 这里**故意**让 NSHostingView 直接当 contentView，是 AGENTS「面板不得用 hosting 当
        // contentView」那条护栏的**已评估例外**——别看到这行就顺手改成 ManualPanelHost：
        //   1. 载体不是 PanelCoordinator 创建的面板，那条护栏管的是"协调器独占 frame 所有权"，
        //      而载体的 frame 归本类，只在创建时写死成 screen.frame，之后再不从内容尺寸推导；
        //   2. 存活期只有一次拖动，换档事务（beginDockSizeChange）会先取消拖动再改几何，
        //      两者碰不上；
        //   3. 至今没观察到尺寸打架（拖动一直正常）。
        // 但它确实是这个模式的第 4 个暴露点。**万一以后出现"起拖瞬间载体尺寸/位置异常"，
        // 第一个怀疑对象就是这里**——届时套 ManualPanelHost 即可，改法与 dock/胶囊/tooltip 相同。
        panel.contentView = host
        return panel
    }

    /// 弹簧开抽屉后把载体重新提到最前——新开的抽屉 orderFront 后可能盖住先于它创建的载体（owner 2026-06-21
    /// 报告"拖进弹簧开的抽屉时浮动图标消失"）。仅拖动进行中才动。
    func bringCarrierToFront() {
        guard draggingPayload != nil, let c = carrierPanel else { return }
        c.orderFrontRegardless()
    }

    /// 屏幕坐标(bottom-left) → 载体面板内 SwiftUI 坐标(top-left, y-down) 的卡片中心位置。
    func carrierPosition() -> CGPoint {
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

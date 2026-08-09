import AppKit
import ApplicationServices
import Combine
import QuartzCore
import SwiftUI
import os

/// 抽屉相关动画的共享时长，AppKit（面板 frame / alpha）和 SwiftUI（内容 scale/网格重排）都用它，
/// 让"面板尺寸滑动"和"内容内部动画"同时长、不错拍（Codex：v1 选面板为主 + 内容同参数）。
enum DrawerAnimation {
    static let duration: TimeInterval = 0.22
}

/// 弹窗/抽屉「面板开合 + 内容入场」动效（快出缓停，贴原生 Stacks 手感，owner 2026-07-06）。
/// 任务条宽度/面板 frame 布局动画仍用 DrawerAnimation.duration=0.22，两组时长不得合并（AGENTS）。
enum PopoverAnimation {
    static let openDuration: TimeInterval = 0.18
    static let closeDuration: TimeInterval = 0.13
    /// 强 ease-out：起步快、收尾缓，原生弹出手感。
    static func curve() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
    }
}

private struct FullscreenIntentTransaction {
    let generation: UInt64
    let pid: pid_t
    let focusedWindowID: CGWindowID
    let screenCGFrame: CGRect
}

/// CAMediaTimingFunction 的数值求解版：CALayer 隐式动画只能按"单一属性"整体插值，
/// 而弹窗切换要按 centerX/bottomY/width/height 四个语义量分别插值再拼回 frame，
/// 只能自己按时间步进算 progress。直接吃调用方已有的 CAMediaTimingFunction，不重复定义
/// 控制点（两个调用点用的曲线不同：PopoverAnimation.curve() 与 .easeInEaseOut）。
/// WebKit UnitBezier 同款：牛顿迭代求解 x(t)=elapsed，再取 y(t) 作为缓动进度，迭代不收敛时二分兜底。
private struct UnitBezierEase {
    private let ax, bx, cx: Double
    private let ay, by, cy: Double

    init(_ timingFunction: CAMediaTimingFunction) {
        var p1 = [Float](repeating: 0, count: 2)
        var p2 = [Float](repeating: 0, count: 2)
        timingFunction.getControlPoint(at: 1, values: &p1)
        timingFunction.getControlPoint(at: 2, values: &p2)
        let (p1x, p1y, p2x, p2y) = (Double(p1[0]), Double(p1[1]), Double(p2[0]), Double(p2[1]))
        cx = 3 * p1x; bx = 3 * (p2x - p1x) - cx; ax = 1 - cx - bx
        cy = 3 * p1y; by = 3 * (p2y - p1y) - cy; ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func sampleDX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveX(_ x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let dx = sampleX(t) - x
            if abs(dx) < 1e-6 { return t }
            let d = sampleDX(t)
            if abs(d) < 1e-6 { break }
            t -= dx / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        while lo < hi {
            let cur = sampleX(t)
            if abs(cur - x) < 1e-6 { return t }
            if x > cur { lo = t } else { hi = t }
            t = (hi - lo) / 2 + lo
        }
        return t
    }

    func progress(at t: Double) -> Double { sampleY(solveX(t)) }
}

@MainActor
final class PanelCoordinator: NSObject {
    /// 面板几何随尺寸档位变，所以这些**不能再是 static**：换档时要跟着 store 走。
    /// `shadowPadding` 例外——它固定 20，视图侧（抽屉、两个弹窗）继续静态引用。
    private var layoutMetrics: PanelLayoutMetrics { settingsStore.dockSize.metrics }
    private var panelHeight: CGFloat { layoutMetrics.panelHeight }
    private var windowHeight: CGFloat { layoutMetrics.windowHeight }
    private var capsuleWidth: CGFloat { layoutMetrics.capsuleWidth }
    static let shadowPadding: CGFloat = PanelLayoutMetrics.shadowPadding

    private let runtime: AppRuntime
    private let drawerStore: DrawerStore
    private let messagingStore: MessagingAppStore
    private let badgeStore: BadgeStore
    private let stripOrderStore: StripOrderStore
    private let drawerOrderStore: DrawerOrderStore
    private let settingsStore: AppSettingsStore
    private let pinnedFolderStore: PinnedFolderStore
    private let folderCoverStore: PinnedFolderCoverStore
    private let shelfStore: ShelfStore
    private let keptAppStore: KeptAppStore
    private let runningApplicationStore: RunningApplicationStore
    private let appMembershipController: AppMembershipController
    /// 外部文件移入固定文件夹的唯一执行队列：资格判断与磁盘操作都按投放批次串行。
    private let fileDropQueue = DispatchQueue(label: "com.caye.macosdockcc.v2.folder-drop", qos: .userInitiated)
    /// 文件夹 chip / 中转格右键「添加文件夹…」入口（AppDelegate 注入，NSOpenPanel 归它管）。
    var onAddFolder: () -> Void = {}
    /// 右键任务条 / 胶囊时弹出钨极菜单。菜单归 `StatusMenuController` 持有，这里只转发事件——
    /// 正常运行时应用是 `.accessory`（没有菜单栏，也就没有 ⌘,），状态栏图标一旦被挤掉或被刘海挡住，
    /// 这就是打开设置的唯一后路。
    var onRequestTaskbarMenu: ((NSEvent, NSView) -> Void)?
    private var dockPanel: NSPanel?
    /// 主任务条的 SwiftUI 承载器。窗口 frame 归 PanelCoordinator，内容尺寸只从这里读取。
    private var dockContentHost: ManualPanelHost?
    private var drawerPanel: NSPanel?
    private var capsulePanel: NSPanel?
    /// 胶囊的 SwiftUI 承载器。胶囊宽高固定（`capsuleWidth`），当前没人读它的 `fittingSize`——
    /// 但仍然**强持有**而不是 `_ =` 丢弃：丢弃后只靠视图层级间接留住容器，哪天给
    /// `ManualPanelHost` 加了 `deinit` 清理，胶囊会静默失效。
    private var capsuleContentHost: ManualPanelHost?
    /// 抽屉真正承载 SwiftUI 的 hosting view（抽屉 contentView 是普通 NSView 容器,故 fittingSize 要读这个）。
    private var drawerContentHost: NSView?
    /// 跨面板拖动（拖卡进抽屉 路线 C）的唯一权威：载体面板 + 鼠标监视器 + 落点收尾都在它里面。
    /// 必须在 setupDockPanel/setupCapsulePanel 之前建好，因为要注入进这两个面板的 hosting。
    private var dragController: DragController!
    /// 权限丢失后的挂起态。刻意**不**复用 `visibilityState.hideReasons`——
    /// 那套是给全屏和边缘自动隐藏用的，混进来会让底边唤醒把面板又拉回屏幕。
    private var isSuspendedForPermissionLoss = false
    private var drawerLocalMonitor: Any?
    private var drawerGlobalMonitor: Any?
    // MARK: 文件夹/中转弹窗状态（单面板复用 = 天然「同时只有一个弹窗」）
    /// 共享弹窗当前装的内容：固定文件夹网格或中转网格。
    enum PopupContent: Equatable {
        case folder(path: String)
        case shelf
    }
    private var folderPopupPanel: NSPanel?
    /// 弹窗真正承载 SwiftUI 的 hosting view（contentView 是普通 NSView 容器,fittingSize 读这个）。
    private var folderPopupContentHost: NSView?
    private var popupLocalMonitor: Any?
    private var popupGlobalMonitor: Any?
    private var lastPopupTargetFrame: NSRect = .zero
    /// 弹窗锚点（chip 可视矩形,屏幕坐标）。click-away 判定要排除它——监视器在 mouseDown 关、
    /// chip 的 onTapGesture 在 mouseUp 又开,不排除锚点则同 chip 点击永远无法收合。
    private var popupAnchorVisibleRect: CGRect = .zero
    /// 当前弹窗内容（nil = 没开）。
    private var openPopupContent: PopupContent?
    /// 便捷视图：仅当弹窗装的是文件夹时给 path（排序订阅/移除关窗等文件夹专属逻辑用）。
    private var openPopupPath: String? {
        if case let .folder(path) = openPopupContent { return path }
        return nil
    }
    /// 弹窗**逻辑**开关态（淡出动画期间面板还可见但逻辑上已关,同 drawerWantsOpen）。
    private var folderPopupWantsOpen = false
    private var lastPopupSize = CGSize(width: 424, height: 240)
    /// 开窗时刻：入场窗口期（250ms）内的重定位一律瞬时,不与入场淡入叠加出晃动。
    private var popupOpenedAt: Date = .distantPast
    /// 弹窗切换/重定位的手搓逐帧插值 timer（按 centerX/bottomY/width/height 插值,取代
    /// NSWindow.animator().setFrame 的原始 x/y/宽/高线性插值——后者没有锚点概念,两个文件夹
    /// frame 相对位置一变,生长方向就随机偏向某个角落,而不是稳定的"贴底、水平居中"）。
    private var folderPopupFrameTimer: Timer?
    /// 每次开一个新 tween 就 +1。tick 回调里核对这个 token 再改 frame——
    /// Timer.invalidate() 挡不住"已经 fire、Task 还排在主 actor 队列里没跑到"的那一次回调,
    /// 光 invalidate 不够,得靠 token 让过期的排队任务自己变成 no-op。
    private var folderPopupTweenToken: Int = 0
    /// 当前在飞 tween 的目标帧（nil = 没在飞）。双重 defer 的兜底校正常带着**同一个**目标再进来,
    /// 若无脑重启就会打断刚起步的动画、重置时钟(速度突变+总时长变长);目标相同直接放行让它走完。
    private var folderPopupTweenTarget: NSRect?
    // MARK: 窗口标题 Tooltip（专属面板，不复用 folderPopupPanel）
    private var windowTitleTooltipPanel: NSPanel?
    private var windowTitleTooltipRequest: WindowTitleTooltipRequest?
    private var windowTitleTooltipSuppressedChipID: String?
    private var windowTitleTooltipTimer: Timer?
    private var windowTitleTooltipLocalMonitor: Any?
    private var windowTitleTooltipGlobalMonitor: Any?
    private var pinnedFolderStoreSubscription: AnyCancellable?
    private var pinnedFolderSortSubscription: AnyCancellable?
    private var snapshotWidthSubscription: AnyCancellable?
    private var drawerStoreWidthSubscription: AnyCancellable?
    private var messagingStoreWidthSubscription: AnyCancellable?
    private var keptAppStoreSubscription: AnyCancellable?
    private var runningApplicationStoreSubscription: AnyCancellable?
    private var dragSpringSubscription: AnyCancellable?
    private var dragInhibitorSubscription: AnyCancellable?
    private var edgeDelaySubscription: AnyCancellable?
    private var fullscreenIntentEnabledSubscription: AnyCancellable?
    private var showShelfSubscription: AnyCancellable?
    private var dockSizeSubscription: AnyCancellable?
    /// 换档事务代次：吞掉换档过程中被其它路径排队的动画布局（见 beginDockSizeChange）。
    private var dockSizeChangeGeneration: UInt64 = 0
    /// 抽屉拖回任务条·"松手才变长"：转正进行中冻结任务条宽度，转正态结束（松手落定 / 拖出还原）再 relayout。
    private var convertReleaseSubscription: AnyCancellable?
    private var springOpenTimer: Timer?
    /// 离开抽屉+胶囊后**延迟收回**的定时器（owner 2026-06-22：要延迟,不要一蹭到任务条就关）。
    private var springCloseTimer: Timer?
    /// 本次拖动是否**从任务条发起**。任务条卡进抽屉体会被"转正"成 `.drawer` 来源（见 DragController），
    /// 但弹簧（开/延迟收/重开）整段拖动都该生效,所以认这个、不认实时 source（owner 2026-06-22）。
    private var dragOriginatedFromStrip = false
    /// 抽屉**逻辑**开关态（不看 isVisible——淡出动画期间面板还可见但逻辑上已关）。toggle/弹簧/可打断关都看它。
    private var drawerWantsOpen = false
    /// 每次 openDrawer() 递增。closeDrawerAfterAction() 捕获当前值，触发时不匹配则丢弃，
    /// 防止旧点击的延迟关闭在抽屉重新打开后误杀新抽屉。
    private var drawerActionCloseToken = 0
    /// 这次抽屉是不是**弹簧**(拖动悬停)打开的。若是、且松手时这张卡没进抽屉(又拖回任务条) → 自动收回。
    private var drawerSpringOpened = false
    /// 正在拖的 strip 卡 bundleID,松手时用它判断有没有收进抽屉。
    private var springDragBundleID: String?
    private var lastDesiredWidth: CGFloat = 0
    /// 跨面板转正进行中钳住的任务条内容宽度（拖动前的值）。非 nil → relayout 用它而非实测宽度，
    /// 让窗口卡溢出/留空而不改变面板宽度；松手/还原清空后下一次 relayout 变到最终长度（owner 2026-06-22）。
    private var frozenDockContentWidth: CGFloat?
    private var lastDrawerSize: CGSize = CGSize(width: 210, height: 60)
    /// 目标 frame 驱动布局：每次 layoutPanels 算齐三个目标并存这里。drop zone 命中、开抽屉定位都读**目标**
    /// 而非 live frame——动画中 live frame 是中途值,会和视觉/逻辑短暂不一致（Codex 二审 P2）。
    private var lastDockTargetFrame: NSRect = .zero
    private var lastCapsuleTargetFrame: NSRect = .zero
    private var lastDrawerTargetFrame: NSRect = .zero
    /// 首帧布局强制瞬时（面板刚建好,别从初始/原点位置滑过来）。
    private var didInitialLayout = false
    private let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "dock-panel")
    private let fullscreenIntentLogger = Logger(
        subsystem: "com.caye.macosdockcc.v2",
        category: "FullscreenIntent"
    )

    private var fullscreenReconcileTimer: Timer?
    private var fullscreenIntentMonitor: FullscreenIntentMonitor?
    private var fullscreenIntentTimeoutTimer: Timer?
    private var fullscreenIntentGeneration: UInt64 = 0
    private var fullscreenIntentTransaction: FullscreenIntentTransaction?
    private var fullscreenProbeGeneration: UInt64 = 0
    private var lastActiveApplicationPID: pid_t?
    private var visibilityState = PanelVisibilityState()
    private var panelsAreVisible = true
    private var edgeIdleHideTimer: Timer?
    private var edgeWakeTimer: Timer?
    private var edgeWakeTargetScreen: NSScreen?
    private var edgeWakeRequiresHotZone = true
    private var hoverLocalMouseMonitor: Any?
    private var hoverGlobalMouseMonitor: Any?

    init(runtime: AppRuntime,
         drawerStore: DrawerStore,
         messagingStore: MessagingAppStore,
         badgeStore: BadgeStore,
         stripOrderStore: StripOrderStore,
         drawerOrderStore: DrawerOrderStore,
         settingsStore: AppSettingsStore,
         pinnedFolderStore: PinnedFolderStore,
         folderCoverStore: PinnedFolderCoverStore,
         shelfStore: ShelfStore,
         keptAppStore: KeptAppStore,
         runningApplicationStore: RunningApplicationStore,
         appMembershipController: AppMembershipController) {
        self.runtime = runtime
        self.drawerStore = drawerStore
        self.messagingStore = messagingStore
        self.badgeStore = badgeStore
        self.stripOrderStore = stripOrderStore
        self.drawerOrderStore = drawerOrderStore
        self.settingsStore = settingsStore
        self.pinnedFolderStore = pinnedFolderStore
        self.folderCoverStore = folderCoverStore
        self.shelfStore = shelfStore
        self.keptAppStore = keptAppStore
        self.runningApplicationStore = runningApplicationStore
        self.appMembershipController = appMembershipController
        super.init()
    }

    func start() {
        setupDragController()
        setupDockPanel()
        setupCapsulePanel()
        presentInitialPanels()
        subscribeSnapshotWidth()
        subscribeDrawerStoreWidth()
        subscribeMessagingStoreWidth()
        subscribeKeptAppStore()
        subscribeRunningApplicationStore()
        subscribeDragSpringLoad()
        subscribeDragInhibitor()
        subscribeConvertRelease()
        subscribeSettings()
        subscribePinnedFolderStore()
        setupFullscreenMonitor()
        reconcileFullscreenIntentMonitor()
        setupHoverDiagnostics()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        fullscreenReconcileTimer?.invalidate()
        fullscreenIntentTimeoutTimer?.invalidate()
        MainActor.assumeIsolated {
            fullscreenIntentMonitor?.stop()
            removeHoverMouseMonitors()
            dismissWindowTitleTooltip()
        }
        edgeIdleHideTimer?.invalidate()
        edgeWakeTimer?.invalidate()
        springOpenTimer?.invalidate()
        springCloseTimer?.invalidate()
        folderPopupFrameTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func toggleDrawer() {
        if drawerWantsOpen { closeDrawer() } else { openDrawer() }
    }

    /// 权限丢失时把整套面板拆干净并交出所有权（调用方随后置空引用即可）。幂等。
    ///
    /// 这里刻意**不**走「手工列一份摘监视器清单」的路子——漏项风险太高：
    /// `DockStripView` 自己在 `NSViewRepresentable` 里装了力度点击 / 中键监视器，
    /// 只有视图树真被拆掉才会触发 `dismantleNSView` 去摘；而 `deinit` 已经覆盖了
    /// hover 监视器和一整排定时器，那份清单会随新增资源一起被维护。
    /// 所以：拆视图树 → 关面板 → 让调用方释放本对象走 `deinit`。
    ///
    /// 不做对称的 resume：权限恢复后是整个进程重启，没有「恢复运行」这条路径。
    func suspendAndRelease() {
        guard !isSuspendedForPermissionLoss else { return }
        isSuspendedForPermissionLoss = true
        fullscreenIntentMonitor?.stop()
        fullscreenIntentMonitor = nil
        fullscreenIntentTimeoutTimer?.invalidate()
        fullscreenIntentTimeoutTimer = nil

        // 先回滚未提交的跨面板拖拽事务，再拆监视器。
        dragController?.cancelDrag()
        closeDrawer()
        closeFolderPopup(immediately: true)
        dismissWindowTitleTooltip()
        cancelHoverSwitch()

        // 换掉 contentView 触发 SwiftUI 拆树；单独强持有的 host 要先置空。
        dockContentHost = nil
        capsuleContentHost = nil
        drawerContentHost = nil
        folderPopupContentHost = nil
        for panel in [dockPanel, capsulePanel, drawerPanel, folderPopupPanel, windowTitleTooltipPanel] {
            guard let panel else { continue }
            panel.contentView = NSView()
            panel.orderOut(nil)
            panel.close()
        }
        dockPanel = nil
        capsulePanel = nil
        drawerPanel = nil
        folderPopupPanel = nil
        windowTitleTooltipPanel = nil
    }

    /// 最大化避让只在钨极常驻且真正可见时取得上下文；一次性返回完整几何，避免切屏时撕裂读取。
    func windowLiftAvoidanceContext() -> WindowLiftAvoidanceContext? {
        guard !settingsStore.edgeAutoHideEnabled,
              visibilityState.isVisible,
              panelsAreVisible,
              let panel = dockPanel else {
            return nil
        }

        let screen = panelCurrentScreen(panel: panel)
        let primaryScreenHeight = Self.quartzPrimaryScreenHeight
        let geometry = WindowLiftAvoidance.Geometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            taskbarTop: screen.frame.minY
                + layoutMetrics.bottomGap
                + layoutMetrics.panelHeight
        )
        return WindowLiftAvoidanceContext(
            geometry: geometry,
            screenCGFrame: Self.toCGRect(screen),
            visibleCGFrame: WindowLiftAvoidance.quartzFrame(
                fromAppKit: screen.visibleFrame,
                primaryScreenHeight: primaryScreenHeight
            ),
            primaryScreenHeight: primaryScreenHeight
        )
    }

    private func openDrawer() {
        guard let mainPanel = dockPanel, capsulePanel != nil else { return }
        drawerActionCloseToken += 1  // 旧点击排队的 delayed close 捕获旧 token，不匹配则丢弃
        drawerWantsOpen = true
        setAutoHideInhibitor(.drawerOpen, active: true)
        drawerSpringOpened = false   // 默认手动开；弹簧路径在 springOpenDrawer 里再置 true

        if drawerPanel == nil {
            let panel = NonConstrainingPanel(
                contentRect: NSRect(origin: .zero, size: lastDrawerSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.isMovable = false
            panel.isOpaque = false
            panel.backgroundColor = NSColor(white: 1.0, alpha: 0.0)
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            drawerPanel = panel
        }
        guard let panel = drawerPanel else { return }

        let screen = panelCurrentScreen(panel: mainPanel)
        let screenGeometry = Self.screenGeometry(screen)
        // 用胶囊**目标** frame 定位（不读 live：用户可能在任务条宽度动画中触发弹簧开抽屉,Codex 二审 P1）。
        let capsuleRef = lastCapsuleTargetFrame == .zero ? (capsulePanel?.frame ?? .zero) : lastCapsuleTargetFrame
        // 抽屉最大内容高度 = 胶囊上方锚点 → 屏幕上沿的可用高度。超出由 DrawerView 内部滚动,
        // 绝不靠下压底边来塞下（否则压向胶囊/任务条 = 重叠,Codex 二审第 4 点）。
        // 顶部上限仍避让菜单栏 / 刘海；底部锚点不避让原生 Dock，避免 Command+Option+D 或侧边 Dock 推动抽屉。
        let maxContentHeight = PanelGeometry.maxDrawerContentHeight(forCapsule: capsuleRef, on: screenGeometry)

        // 每次打开都换一份新内容视图 → DrawerView 的 onAppear 重新触发淡入缩放,并拿到当前 maxContentHeight。
        let hosting = NSHostingView(rootView: DrawerView(maxContentHeight: maxContentHeight,
                                                         onPrimaryAction: { [weak self] in self?.closeDrawerAfterAction() })
            .environmentObject(runtime).environmentObject(drawerStore).environmentObject(messagingStore)
            .environmentObject(drawerOrderStore).environmentObject(dragController)
            .environmentObject(keptAppStore).environmentObject(runningApplicationStore)
            .environmentObject(appMembershipController))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor

        // 关键：用普通 NSView 当 contentView,hosting 作为子视图自适应填充——**不让 NSHostingView 直接当 contentView**。
        // 否则内容变高时 macOS 会用内容尺寸**顶边锚定、向下撑大**窗口（日志实测 cur(y=24 h=194)、top 恒=218），
        // 我们的布局随后才把它纠正成底边锚定向上长（y=68）——这一前一后打架 = owner 看到的"先向下扩展再上移"
        // 的真因（2026-06-22）。普通 NSView 不把子视图内容尺寸传给窗口,窗口高度只由 layoutPanels/setFrames 控制;
        // fittingSize 改读 hosting（存进 drawerContentHost）。
        let container = NSView(frame: NSRect(origin: .zero, size: lastDrawerSize))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        drawerContentHost = hosting

        // 首帧就位（owner 2026-07-06「不丝滑」主因之一）：orderFront **前**同步量真实尺寸,
        // 首帧即最终大小,不再「旧尺寸弹出→瞬间校正」。量不到合理值退回 lastDrawerSize,
        // 后面的 double-defer 复测仍在,作兜底校正。
        panel.layoutIfNeeded()
        let sync = hosting.fittingSize
        if sync.width >= 60, sync.height >= 60 {
            lastDrawerSize = sync
        }
        let initialFrame = drawerTargetFrame(forCapsule: capsuleRef, size: lastDrawerSize, on: screen)
        lastDrawerTargetFrame = initialFrame

        panel.setFrame(initialFrame, display: false)
        if !panel.isVisible { panel.alphaValue = 0 }   // 重开中途若仍可见,从当前 alpha 续上,不跳回 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = PopoverAnimation.openDuration
            ctx.timingFunction = PopoverAnimation.curve()
            panel.animator().alphaValue = 1
        }
        // 弹出后复测 fittingSize 重新布局（瞬时,刚弹出不滑）——同步量偏差时的兜底校正。
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.relayout(animated: false)
            }
        }

        drawerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dismissDrawerIfOutside()
            return event
        }
        drawerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dismissDrawerIfOutside()
        }
    }

    /// 抽屉内点击 app 主操作后的延迟关闭。捕获 token，触发时三重确认才关：
    /// 1. token 匹配（排除抽屉在延迟期被重开的情况）；2. 抽屉仍是逻辑打开态；3. 无拖动进行中。
    private func closeDrawerAfterAction() {
        let token = drawerActionCloseToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self,
                  self.drawerActionCloseToken == token,
                  self.drawerWantsOpen,
                  self.dragController.draggingPayload == nil else { return }
            self.closeDrawer()
        }
    }

    /// 可打断淡出关闭：立即摘监视器、动画 alpha→0,completion 里确认仍要关才 orderOut（淡出中又打开则不关）。
    private func closeDrawer() {
        guard drawerWantsOpen else { return }
        drawerWantsOpen = false
        setAutoHideInhibitor(.drawerOpen, active: false)
        drawerSpringOpened = false
        if let m = drawerLocalMonitor  { NSEvent.removeMonitor(m); drawerLocalMonitor  = nil }
        if let m = drawerGlobalMonitor { NSEvent.removeMonitor(m); drawerGlobalMonitor = nil }
        guard let panel = drawerPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = PopoverAnimation.closeDuration
            ctx.timingFunction = PopoverAnimation.curve()
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.drawerWantsOpen else { return }   // 淡出中又开了 → 别 orderOut
                panel.orderOut(nil)
            }
        })
    }

    /// 全屏输入已经被 tap 暂停投递，不能等淡出动画；状态和监视器照常收口后立即移出 WindowServer。
    private func closeDrawerImmediately() {
        guard drawerWantsOpen || drawerPanel?.isVisible == true else { return }
        drawerWantsOpen = false
        setAutoHideInhibitor(.drawerOpen, active: false)
        drawerSpringOpened = false
        if let monitor = drawerLocalMonitor {
            NSEvent.removeMonitor(monitor)
            drawerLocalMonitor = nil
        }
        if let monitor = drawerGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            drawerGlobalMonitor = nil
        }
        drawerPanel?.alphaValue = 0
        drawerPanel?.orderOut(nil)
    }

    private func dismissDrawerIfOutside() {
        guard dragController.draggingPayload == nil else { return }   // 拖动中不误关
        guard let drawer = drawerPanel, drawer.isVisible,
              let dock   = dockPanel else { return }
        let mouse = NSEvent.mouseLocation
        guard !drawer.frame.contains(mouse),
              !dock.frame.contains(mouse),
              !(capsulePanel?.frame.contains(mouse) ?? false) else { return }
        closeDrawer()
    }

    // MARK: - 文件夹/废纸篓弹窗（克隆抽屉模板：懒面板 + 普通容器包 hosting + 淡入淡出 + click-away 监视器）

    /// chip 点击入口：同一文件夹再点 = 收起；换文件夹 = 瞬时切换目标。anchorVisibleRect 是 chip 可视矩形（屏幕坐标）。
    func toggleFolderPopup(path: String, anchorVisibleRect: CGRect) {
        if folderPopupWantsOpen, openPopupContent == .folder(path: path) {
            closeFolderPopup()
        } else {
            openFolderPopup(path: path, anchorVisibleRect: anchorVisibleRect)
        }
    }

    /// 中转格点击入口：再点 = 收起；从文件夹弹窗切过来 = 原地切换（同单面板语义）。
    func toggleShelfPopup(anchorVisibleRect: CGRect) {
        if folderPopupWantsOpen, openPopupContent == .shelf {
            closeFolderPopup()
        } else {
            openShelfPopup(anchorVisibleRect: anchorVisibleRect)
        }
    }

    private func openFolderPopup(path: String, anchorVisibleRect: CGRect) {
        let rootURL = URL(fileURLWithPath: path)
        let sortOrder = pinnedFolderStore.sortOrder(for: path)
        // 混合兜底：先查热缓存（0ms，且校验了排序一致性），Miss 则回退到短时 preload（最多阻塞 150ms），确保首帧完整。
        let preloadedEntries = folderCoverStore.cachedEntries(for: path, order: sortOrder)
            ?? FolderContentsLoader.preload(url: rootURL, timeout: 0.15, order: sortOrder)
        // 首帧完整**包含图标**：预热首批可见格（8 列 × 网格高上限 ≈ 40 格,取 48 宽裕值）的图标缓存,
        // 否则格子先出、图标按解析顺序从左上角逐个浮现（owner 2026-07-07 报的"从左上角出现"真因）。
        if let entries = preloadedEntries {
            FolderIconResolver.warm(paths: entries.prefix(48).map(\.url.path), timeout: 0.1)
        }

        presentPopup(content: .folder(path: path), anchorVisibleRect: anchorVisibleRect) { [weak self] maxContentHeight in
            NSHostingView(rootView: FolderGridPopupView(
                rootURL: rootURL,
                initialEntries: preloadedEntries,
                sortOrder: sortOrder,
                maxContentHeight: maxContentHeight,
                onFileOpened: { [weak self] in self?.closeFolderPopup() },
                onContentResize: { [weak self] in self?.repositionFolderPopup(animated: true) },
                onPinFolder: { [weak self] url in self?.pinnedFolderStore.add(url.path) },
                isFolderPinned: { [weak self] url in self?.pinnedFolderStore.contains(url.path) ?? true }
            ))
        }
    }

    private func openShelfPopup(anchorVisibleRect: CGRect) {
        shelfStore.prune()   // 打开即剔除已失效的引用（文件被移走/删除）
        // 同 openFolderPopup：首帧图标全亮,不逐个浮现。
        FolderIconResolver.warm(paths: Array(shelfStore.itemPaths.prefix(48)), timeout: 0.1)

        presentPopup(content: .shelf, anchorVisibleRect: anchorVisibleRect) { [weak self, shelfStore] maxContentHeight in
            NSHostingView(rootView: ShelfGridPopupView(
                shelfStore: shelfStore,
                maxContentHeight: maxContentHeight,
                onClosePopup: { [weak self] in self?.closeFolderPopup() },
                onContentResize: { [weak self] in self?.repositionFolderPopup(animated: true) },
                onPinFolder: { [weak self] url in self?.pinnedFolderStore.add(url.path) },
                isFolderPinned: { [weak self] url in self?.pinnedFolderStore.contains(url.path) ?? true }
            ))
        }
    }

    /// 共享的弹窗呈现路径（文件夹/中转同一面板同一套动画与监视器）。内容构建交给 makeHosting
    /// （入参 = 网格可用高度上限）；调用方负责先做好各自的预载（首帧完整,AGENTS 护栏）。
    private func presentPopup(content: PopupContent, anchorVisibleRect: CGRect, makeHosting: (CGFloat) -> NSView) {
        guard let mainPanel = dockPanel else { return }
        // 可打断：面板可见时换内容**原地切换**——不 orderOut（根除黑一下的 blink），
        // 只撤旧监视器（随后重装），内容瞬换、帧滑向新目标。仅淡出中/未开时才走关闭路径。
        let isSwitching = folderPopupWantsOpen && (folderPopupPanel?.isVisible ?? false)
        if folderPopupWantsOpen {
            if isSwitching {
                if let m = popupLocalMonitor  { NSEvent.removeMonitor(m); popupLocalMonitor  = nil }
                if let m = popupGlobalMonitor { NSEvent.removeMonitor(m); popupGlobalMonitor = nil }
            } else {
                closeFolderPopup(immediately: true)
            }
        }

        if folderPopupPanel == nil {
            let panel = NonConstrainingPanel(
                contentRect: NSRect(origin: .zero, size: lastPopupSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.isMovable = false
            panel.isOpaque = false
            panel.backgroundColor = NSColor(white: 1.0, alpha: 0.0)
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            folderPopupPanel = panel
        }
        guard let panel = folderPopupPanel else { return }

        let screen = panelCurrentScreen(panel: mainPanel)
        let screenGeometry = Self.screenGeometry(screen)
        let maxContentHeight = PanelGeometry.maxFolderPopupContentHeight(
            anchorVisibleRect: anchorVisibleRect, on: screenGeometry, metrics: layoutMetrics)

        let hosting = makeHosting(maxContentHeight)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor

        popupAnchorVisibleRect = anchorVisibleRect
        openPopupContent = content
        folderPopupWantsOpen = true
        setAutoHideInhibitor(.folderPopupOpen, active: true)

        // 同抽屉：普通 NSView 容器 + hosting 钉入,防 NSHostingView 当 contentView 时顶边锚定向下撑（AGENTS 护栏）。
        let container = NSView(frame: NSRect(origin: .zero, size: lastPopupSize))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        folderPopupContentHost = hosting

        // 首帧就位（owner 2026-07-06「不丝滑」主因之一）：orderFront **前**同步量真实尺寸,
        // 首帧即最终大小,不再「旧尺寸弹出→瞬间校正」。量不到合理值退回 lastPopupSize,
        // 后面的 double-defer 复测仍在,作兜底校正。
        panel.layoutIfNeeded()
        let sync = hosting.fittingSize
        if sync.width >= 160, sync.height >= 100 {
            lastPopupSize = sync
        }
        let initialFrame = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchorVisibleRect, size: lastPopupSize, on: screenGeometry, metrics: layoutMetrics)
        lastPopupTargetFrame = initialFrame

        if isSwitching {
            // 原地切换：alpha 保持 1,帧从当前位置滑向新目标,内容已瞬换。随时可再切（可打断）。
            animateFolderPopupFrame(
                panel: panel, to: initialFrame,
                duration: PopoverAnimation.openDuration, timingFunction: PopoverAnimation.curve())
        } else {
            // 首帧就位后整体淡入：panel.alphaValue 0→1 把背景/网格/阴影当一块淡进来
            // （内容层不再另做缩放/透明度,见 FolderGridPopupView）。
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                panel.setFrame(initialFrame, display: false)
            }
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = PopoverAnimation.openDuration
                ctx.timingFunction = PopoverAnimation.curve()
                panel.animator().alphaValue = 1
            }
        }
        popupOpenedAt = Date()
        // 弹出后复测 fittingSize（双重 defer 等 SwiftUI 布局完成）——同步量偏差时的兜底校正,瞬时。
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.repositionFolderPopup(animated: false)
            }
        }

        popupLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dismissFolderPopupIfOutside()
            return event
        }
        popupGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dismissFolderPopupIfOutside()
        }
    }

    /// 内容尺寸变化（首测/下钻/实时刷新）→ 按锚点重算目标帧。宽高都由内容推导（列数确定宽）。
    private func repositionFolderPopup(animated: Bool) {
        guard folderPopupWantsOpen,
              let panel = folderPopupPanel,
              let hosting = folderPopupContentHost,
              let dock = dockPanel else { return }
        // 入场窗口期内一律瞬时校正,不与入场淡入叠加出晃动（散装感修复）。
        let animated = animated && Date().timeIntervalSince(popupOpenedAt) > 0.25
        let fitting = hosting.fittingSize
        let size = CGSize(width: max(fitting.width, 160), height: max(fitting.height, 120))
        lastPopupSize = size
        let screen = panelCurrentScreen(panel: dock)
        let target = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: popupAnchorVisibleRect, size: size, on: Self.screenGeometry(screen), metrics: layoutMetrics)
        lastPopupTargetFrame = target

        if folderPopupFrameTimer != nil {
            // 正有一个手搓 tween 在飞（多半是刚触发的切换动画）——双重 defer 的兜底校正不能瞬时打断它,
            // 只把它的终点纠正到最新测量值,继续飞（不然切换动画刚起步就被这里焊死到终点）。
            animateFolderPopupFrame(
                panel: panel, to: target,
                duration: PopoverAnimation.openDuration, timingFunction: PopoverAnimation.curve())
        } else if animated {
            animateFolderPopupFrame(
                panel: panel, to: target,
                duration: Self.layoutAnimationDuration, timingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// 弹窗切换/重定位 tween 的统一取消入口：invalidate 挡不住"已经 fire、Task 还没跑到"的那一次
    /// 回调,靠 token 递增让过期的排队任务在 tick 里自己变成 no-op。
    private func cancelFolderPopupFrameTween() {
        folderPopupFrameTimer?.invalidate()
        folderPopupFrameTimer = nil
        folderPopupTweenTarget = nil
        folderPopupTweenToken &+= 1
    }

    /// 弹窗切换/重定位 tween 的每帧 frame 计算：不直接插值两个已经各自算好、各自钳位过的端点位置
    /// （那样会把"要不要钳位"这件事当成两点间的直线搬移，忽略了钳位只在宽度够大时才触发的
    /// 非线性——宽内容贴边、窄内容不贴边，直线插值会在中途出现方向不自然的滑动）。
    /// 改成插值"期望中心点"（未钳位的锚点中心）+ 宽高，每帧重新走一遍居中+钳位公式，
    /// 与 `PanelGeometry.folderPopupTargetFrame` 同一套规则，保证任何中间尺寸都表现得
    /// 像"用这个尺寸真的锚定在这个 chip 上"。
    /// 首帧起点用 `start.midX`/`start.minY` 而不是"旧锚点"——start 本身永远是当前合法、
    /// 已经在屏幕内的 frame，用它自己的中心反推永远精确等于 start，天然保证 p=0 时不瞬移；
    /// 终点用 `popupAnchorVisibleRect`（当前/新锚点的原始位置）配合插值到 target 的宽度，
    /// 同样保证 p=1 精确落回 target（AGENTS「只向上生长」的设计意图）。
    private func animateFolderPopupFrame(
        panel: NSPanel, to target: NSRect, duration: TimeInterval, timingFunction: CAMediaTimingFunction
    ) {
        // 已经在飞向同一目标 → 别重启,让它按原时钟走完（双重 defer 兜底校正的常见情形,
        // 重启会打断刚起步的动画、重置进度时钟,凭空制造速度突变+更长时长）。
        if folderPopupFrameTimer != nil, folderPopupTweenTarget == target { return }
        cancelFolderPopupFrameTween()
        let token = folderPopupTweenToken

        let start = panel.frame
        guard start != target, duration > 0, let dock = dockPanel else {
            panel.setFrame(target, display: true)
            return
        }
        let screen = Self.screenGeometry(panelCurrentScreen(panel: dock))

        let ease = UnitBezierEase(timingFunction)
        let (w0, w1) = (start.width, target.width)
        let (h0, h1) = (start.height, target.height)
        let startCenterX = start.midX
        let endCenterX = popupAnchorVisibleRect.midX
        let startBottomY = start.minY
        let endBottomY = popupAnchorVisibleRect.maxY + 8
        let clockStart = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self, self.folderPopupTweenToken == token, let panel = self.folderPopupPanel else {
                    t.invalidate()
                    return
                }
                let raw = min(max((CACurrentMediaTime() - clockStart) / duration, 0), 1)
                if raw >= 1 {
                    panel.setFrame(target, display: true)   // 落到精确目标值,不依赖浮点误差刚好踩中 1.0
                    self.folderPopupFrameTimer = nil
                    self.folderPopupTweenTarget = nil
                    t.invalidate()
                } else {
                    let p = ease.progress(at: raw)
                    let width = w0 + (w1 - w0) * p
                    let height = h0 + (h1 - h0) * p
                    // 每帧用当前尺寸重走 PanelGeometry 的居中+钳位公式（与首帧/重定位同一真相）。
                    let origin = PanelGeometry.folderPopupClampedOrigin(
                        desiredCenterX: startCenterX + (endCenterX - startCenterX) * p,
                        desiredBottomY: startBottomY + (endBottomY - startBottomY) * p,
                        size: CGSize(width: width, height: height), on: screen)
                    panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
                }
            }
        }
        folderPopupFrameTimer = timer
        folderPopupTweenTarget = target
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 可打断淡出关闭（同 closeDrawer）。immediately=true 用于换目标瞬切。
    func closeFolderPopup(immediately: Bool = false) {
        guard folderPopupWantsOpen else { return }
        folderPopupWantsOpen = false
        openPopupContent = nil
        setAutoHideInhibitor(.folderPopupOpen, active: false)
        if let m = popupLocalMonitor  { NSEvent.removeMonitor(m); popupLocalMonitor  = nil }
        if let m = popupGlobalMonitor { NSEvent.removeMonitor(m); popupGlobalMonitor = nil }
        cancelFolderPopupFrameTween()   // 关闭时任何在飞的 tween 都要停,免得 orderOut 之后还偷偷挪 frame
        guard let panel = folderPopupPanel else { return }

        if immediately {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = PopoverAnimation.closeDuration
            ctx.timingFunction = PopoverAnimation.curve()
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.folderPopupWantsOpen else { return }   // 淡出中又开了 → 别 orderOut
                panel.orderOut(nil)
            }
        })
    }

    /// click-away：弹窗内不关；**锚点 chip（+4pt 容差）内也不关**——监视器在 mouseDown 关、chip 的
    /// onTapGesture 在 mouseUp 又开,不排除锚点则同 chip 点击永远开↔关抖动（评审确认的竞态,勿删）。
    private func dismissFolderPopupIfOutside() {
        guard folderPopupWantsOpen, let panel = folderPopupPanel else { return }
        let mouse = NSEvent.mouseLocation
        guard !panel.frame.contains(mouse),
              !popupAnchorVisibleRect.insetBy(dx: -4, dy: -4).contains(mouse) else { return }
        closeFolderPopup()
    }

    /// 固定文件夹名单变化：同步封面 watcher、被移除文件夹的弹窗要关、任务条宽度重排。
    private func subscribePinnedFolderStore() {
        pinnedFolderStoreSubscription = pinnedFolderStore.$folderPaths
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paths in
                guard let self else { return }
                self.folderCoverStore.sync(paths: paths)
                if let openPath = self.openPopupPath, !paths.contains(openPath) {
                    self.closeFolderPopup()
                }
                DispatchQueue.main.async { [weak self] in self?.relayout(animated: true) }
            }
        // 某文件夹排序方式变化：封面要换成新排序的第一个文件;该文件夹弹窗开着 → 走原地切换
        // 路径按新排序重开（面板不灭,内容瞬换;下钻状态重置为接受的边缘,原生 Stacks 同款）。
        pinnedFolderSortSubscription = pinnedFolderStore.$sortOrders
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.folderCoverStore.sync(paths: self.pinnedFolderStore.folderPaths)
                if let openPath = self.openPopupPath {
                    self.openFolderPopup(path: openPath, anchorVisibleRect: self.popupAnchorVisibleRect)
                }
            }
    }

    // MARK: - Drag Controller (拖卡进抽屉 路线 C)

    private func setupDragController() {
        dragController = DragController(
            drawerStore: drawerStore,
            messagingStore: messagingStore,
            dropZonesProvider: { [weak self] source in self?.dragDropZones(for: source) ?? [] },
            screenProvider: { [weak self] in self?.carrierTargetScreen() ?? (NSScreen.main ?? NSScreen.screens[0]) },
            carrierFactory: { [runtime = self.runtime,
                               drawerStore = self.drawerStore,
                               messagingStore = self.messagingStore,
                               folderCoverStore = self.folderCoverStore,
                               keptAppStore = self.keptAppStore,
                               runningApplicationStore = self.runningApplicationStore,
                               appMembershipController = self.appMembershipController,
                               settingsStore = self.settingsStore] controller in
                NSHostingView(rootView: DragCarrierView(controller: controller)
                    .environmentObject(runtime)
                    .environmentObject(drawerStore)
                    .environmentObject(messagingStore)
                    .environmentObject(folderCoverStore)
                    .environmentObject(keptAppStore)
                    .environmentObject(runningApplicationStore)
                    .environmentObject(appMembershipController)
                    .environmentObject(settingsStore))
            }
        )
        // 文件夹 chip 拖动落定：几何由 DockStripView 写入 DragController，最终 mouseUp/轮询兜底在
        // endDrag 里回调到这里执行副作用。保持 .folder 与 strip/drawer 收纳语义隔离。
        dragController.onFolderDragEnded = { [weak self] path, zone in
            guard let self else { return }
            switch zone {
            case .folderZone:
                break
            case .outsideStrip:
                self.pinnedFolderStore.remove(path)
            case .liveZone:
                self.pinnedFolderStore.remove(path)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
        // 抽屉拖回任务条·精确落点：成功松手落定时清顺序层的外部块暂存追踪（boundIDs 已是正常成员、留任务条）。
        dragController.onDrawerToStripCommitted = { [stripOrderStore] _ in
            stripOrderStore.commitExternalBlock()
        }
        // 抽屉拖回任务条·异常取消（cancelDrag）：回滚顺序层的外部块暂存（删 boundIDs + 清 absentSince + 清暂存）。
        dragController.onDrawerToStripCancelled = { [stripOrderStore] in
            stripOrderStore.cancelExternalBlock()
        }
        // 抽屉图标落进任务条（精确落点 + 降级路径都触发）→ 关闭抽屉。
        dragController.onDrawerToStripCompleted = { [weak self] _ in
            self?.closeDrawerAfterAction()
        }
    }

    /// 投放候选区（屏幕坐标），按拖动来源分：
    /// - `.strip` / `.messaging`（任务条卡/消息 chip 找收纳目标）= 胶囊可见内容区 + 8pt 容错（胶囊 frame 含
    ///   shadowPadding=20 透明边，减 20 得 52×52 可见区，再外扩 8 容错，不能更宽——胶囊紧挨任务条，太宽会
    ///   "拖到附近就被收走"）；抽屉打开时叠加抽屉可见内容区。任务条本身不是它们的投放区。
    /// - `.drawer`（抽屉图标找移回目标）= 任务条 dock 面板可见内容区（减 shadowPadding）。
    private func dragDropZones(for source: DragSource) -> [CGRect] {
        // 读**目标** frame：动画中 live frame 是中途值,会和视觉/落点短暂错位（Codex 二审 P2）。目标未初始化时退回 live。
        func target(_ stored: NSRect, _ live: NSRect?) -> NSRect? { stored != .zero ? stored : live }
        switch source {
        case .strip, .messaging:
            var zones: [CGRect] = []
            if let c = target(lastCapsuleTargetFrame, capsulePanel?.frame) {
                zones.append(c.insetBy(dx: Self.shadowPadding - 8, dy: Self.shadowPadding - 8))
            }
            if let drawer = drawerPanel, drawer.isVisible, let d = target(lastDrawerTargetFrame, drawer.frame) {
                // 抽屉只向上长：投放区**上沿拉到屏幕顶**,只认固定的底边+宽度,不随面板增高/缩短而变。
                // 否则"投放区尺寸→是否插空格→面板增高→投放区尺寸"成反馈环,空格闪烁、面板动画被高频打断
                // 而过冲向下（owner 2026-06-21"先向下扩展再上移"的真因）。
                let inset = d.insetBy(dx: Self.shadowPadding, dy: Self.shadowPadding)
                // 投放区向上延伸到与抽屉一致的顶部上限：避让菜单栏/刘海，但不避让原生 Dock。
                let top = Self.screenGeometry(panelCurrentScreen(panel: drawer)).topUsableY
                zones.append(CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: max(inset.height, top - inset.minY)))
            }
            return zones
        case .drawer:
            guard let d = target(lastDockTargetFrame, dockPanel?.frame) else { return [] }
            return [d.insetBy(dx: Self.shadowPadding, dy: Self.shadowPadding)]
        case .folder:
            // 文件夹 chip 无投放区（canExternalDrop=false 本就不会查;区内重排/拖出移除/拖回打开
            // 全在 DockStripView 用 FolderChipDropZone 判定）。与 strip/drawer 收纳语义隔离（评审拍板）。
            return []
        }
    }

    private func carrierTargetScreen() -> NSScreen {
        if let dock = dockPanel { return panelCurrentScreen(panel: dock) }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - 弹簧文件夹：拖卡悬停胶囊自动弹开抽屉

    /// strip 卡悬在胶囊上（抽屉关着时投放区只有胶囊）约 0.4s → 自动弹开抽屉,之后移进抽屉即接上精确定位;
    /// 不等它开、直接在胶囊松手仍按"收进末尾"。移开/松手取消定时器。
    private func subscribeDragSpringLoad() {
        // 订阅 globalLocation（不是 isOverDropZone）——光标回到任务条上不改 isOverDropZone,
        // 必须靠位置才能实时收回抽屉（owner 2026-06-21：拖回任务条即收、再移回胶囊再开）。
        dragSpringSubscription = dragController.$globalLocation
            .combineLatest(dragController.$draggingPayload)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location, payload in
                self?.updateSpringLoad(location: location, payload: payload)
            }
    }

    private func subscribeDragInhibitor() {
        dragInhibitorSubscription = dragController.$draggingPayload
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dragging in
                if dragging { self?.dismissWindowTitleTooltip(suppressCurrentUntilExit: true) }
                self?.setAutoHideInhibitor(.dragging, active: dragging)
            }
    }

    // MARK: - Window title tooltip

    private func handleWindowTitleTooltipEvent(_ event: WindowTitleTooltipEvent) {
        switch event {
        case let .update(request):
            if windowTitleTooltipSuppressedChipID == request.chipID { return }
            windowTitleTooltipSuppressedChipID = nil
            if windowTitleTooltipRequest?.chipID == request.chipID {
                windowTitleTooltipRequest = request
                if windowTitleTooltipPanel?.isVisible == true {
                    presentWindowTitleTooltip(request, animated: false)
                }
                return
            }

            dismissWindowTitleTooltip()
            windowTitleTooltipRequest = request
            installWindowTitleTooltipMouseMonitors()
            let chipID = request.chipID
            let timer = Timer(timeInterval: 0.7, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let current = self.windowTitleTooltipRequest,
                          current.chipID == chipID else { return }
                    self.windowTitleTooltipTimer = nil
                    self.presentWindowTitleTooltip(current, animated: true)
                }
            }
            windowTitleTooltipTimer = timer
            RunLoop.main.add(timer, forMode: .common)

        case let .exit(chipID):
            if windowTitleTooltipSuppressedChipID == chipID {
                windowTitleTooltipSuppressedChipID = nil
            }
            guard windowTitleTooltipRequest?.chipID == chipID else { return }
            dismissWindowTitleTooltip()
        }
    }

    private func presentWindowTitleTooltip(_ request: WindowTitleTooltipRequest, animated: Bool) {
        guard request.anchorVisibleRect != .zero else { return }
        let panel: NSPanel
        if let existing = windowTitleTooltipPanel {
            panel = existing
        } else {
            let created = NonConstrainingPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            created.isFloatingPanel = true
            created.isMovable = false
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.ignoresMouseEvents = true
            windowTitleTooltipPanel = created
            panel = created
        }

        let hosting = NSHostingView(rootView: WindowTitleTooltipView(title: request.title))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let contentHost = ManualPanelHost(contentView: hosting, in: panel)
        panel.layoutIfNeeded()
        let size = contentHost.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let anchorPoint = CGPoint(x: request.anchorVisibleRect.midX, y: request.anchorVisibleRect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) })
            ?? dockPanel.map { panelCurrentScreen(panel: $0) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let target = PanelGeometry.windowTitleTooltipTargetFrame(
            anchorVisibleRect: request.anchorVisibleRect,
            size: size,
            on: Self.screenGeometry(screen)
        )
        panel.setFrame(target, display: true)

        guard animated, !panel.isVisible else {
            panel.alphaValue = 1
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func installWindowTitleTooltipMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        windowTitleTooltipLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
            return event
        }
        windowTitleTooltipGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
        }
    }

    private func dismissWindowTitleTooltip(suppressCurrentUntilExit: Bool = false) {
        if suppressCurrentUntilExit, let chipID = windowTitleTooltipRequest?.chipID {
            windowTitleTooltipSuppressedChipID = chipID
        }
        windowTitleTooltipTimer?.invalidate()
        windowTitleTooltipTimer = nil
        windowTitleTooltipRequest = nil
        if let monitor = windowTitleTooltipLocalMonitor {
            NSEvent.removeMonitor(monitor)
            windowTitleTooltipLocalMonitor = nil
        }
        if let monitor = windowTitleTooltipGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            windowTitleTooltipGlobalMonitor = nil
        }
        windowTitleTooltipPanel?.alphaValue = 0
        windowTitleTooltipPanel?.orderOut(nil)
    }

    /// 视区命中：目标 frame 取可见内容区 + 6pt 迟滞（防胶囊/任务条交界反复横跳）。
    private func springZone(_ target: NSRect) -> CGRect {
        target.insetBy(dx: Self.shadowPadding - 6, dy: Self.shadowPadding - 6)
    }

    private func updateSpringLoad(location: CGPoint, payload: DragPayload?) {
        // 整段拖动只要从任务条发起就享受弹簧（转正成 .drawer 后仍认这个标记）。消息区 chip 同享：
        // 悬胶囊自动弹开抽屉才有精确收纳落点。
        if let p = payload, p.source == .strip || p.source == .messaging {
            dragOriginatedFromStrip = true; springDragBundleID = p.bundleID
        }

        // 松手兜底：弹簧开的抽屉若没把卡收进抽屉 → 收回。（实时悬停大多已处理,这里兜底。）
        if payload == nil {
            cancelSpringTimers()
            if drawerSpringOpened, let bid = springDragBundleID, !drawerStore.contains(bid) {
                closeDrawer()
            }
            drawerSpringOpened = false
            springDragBundleID = nil
            dragOriginatedFromStrip = false
            return
        }
        // 非任务条发起（纯抽屉内拖动 / 抽屉→任务条移回）不弹簧。
        guard dragOriginatedFromStrip else { cancelSpringTimers(); return }

        let inDrawer  = drawerWantsOpen && lastDrawerTargetFrame != .zero && springZone(lastDrawerTargetFrame).contains(location)
        let inCapsule = lastCapsuleTargetFrame != .zero && springZone(lastCapsuleTargetFrame).contains(location)

        if inDrawer || inCapsule {
            // 在抽屉或胶囊上 → 取消收回；关着且在胶囊上 → 起开抽屉定时器。
            springCloseTimer?.invalidate(); springCloseTimer = nil
            if !drawerWantsOpen {
                if inCapsule && springOpenTimer == nil { armSpringOpenTimer() }
            } else {
                springOpenTimer?.invalidate(); springOpenTimer = nil      // 已开 → 保持
            }
        } else {
            // 离开抽屉+胶囊（任务条上或空隙）→ 取消未触发的开；开着则**延迟**收回（owner 2026-06-22）。
            springOpenTimer?.invalidate(); springOpenTimer = nil
            if drawerWantsOpen && springCloseTimer == nil { armSpringCloseTimer() }
        }
    }

    private func cancelSpringTimers() {
        springOpenTimer?.invalidate(); springOpenTimer = nil
        springCloseTimer?.invalidate(); springCloseTimer = nil
    }

    private func armSpringOpenTimer() {
        // .common 模式：拖动时主 run loop 在事件跟踪模式,scheduledTimer(默认 default) 拖动期间不触发。
        let timer = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.springOpenDrawer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        springOpenTimer = timer
    }

    /// 离开抽屉+胶囊 ~0.35s 后才收回（短暂蹭过任务条/空隙不收）。到点仍在拖、仍开、仍在外才真关。
    private func armSpringCloseTimer() {
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.springCloseDrawerIfStillOutside() }
        }
        RunLoop.main.add(timer, forMode: .common)
        springCloseTimer = timer
    }

    private func springCloseDrawerIfStillOutside() {
        springCloseTimer = nil
        guard dragOriginatedFromStrip, drawerWantsOpen else { return }
        let loc = dragController.globalLocation
        let inDrawer  = lastDrawerTargetFrame != .zero && springZone(lastDrawerTargetFrame).contains(loc)
        let inCapsule = lastCapsuleTargetFrame != .zero && springZone(lastCapsuleTargetFrame).contains(loc)
        guard !inDrawer, !inCapsule else { return }   // 又回到抽屉/胶囊 → 不关
        closeDrawer()
    }

    private func springOpenDrawer() {
        springOpenTimer = nil
        // 到点仍在拖、仍悬胶囊、抽屉仍关 → 弹开。用 dragOriginatedFromStrip + 重测胶囊命中（不用
        // isOverDropZone：转正成 .drawer 后它指的是任务条区,悬胶囊时为 false,会误拦重开。owner 2026-06-22）。
        let loc = dragController.globalLocation
        let inCapsule = lastCapsuleTargetFrame != .zero && springZone(lastCapsuleTargetFrame).contains(loc)
        guard dragController.draggingPayload != nil,
              dragOriginatedFromStrip,
              inCapsule,
              !drawerWantsOpen else { return }
        openDrawer()
        drawerSpringOpened = true   // openDrawer 把它置 false 了,这里标记是弹簧开的
        dragController.bringCarrierToFront()
    }

    private func setupDockPanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let s = screen.frame

        let panel = NonConstrainingPanel(
            contentRect: NSRect(x: s.minX, y: s.minY + layoutMetrics.bottomGap - Self.shadowPadding, width: s.width, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 1.0, alpha: 0.0)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: DockStripView(
            onFolderPopupToggle: { [weak self] path, anchorRect in
                self?.toggleFolderPopup(path: path, anchorVisibleRect: anchorRect)
            },
            onShelfPopupToggle: { [weak self] anchorRect in
                self?.toggleShelfPopup(anchorVisibleRect: anchorRect)
            },
            onAddFolder: { [weak self] in self?.onAddFolder() },
            onMoveExternalFiles: { [weak self] urls, path in
                self?.moveExternalFiles(urls, into: path)
            },
            onWindowTitleTooltipEvent: { [weak self] event in
                self?.handleWindowTitleTooltipEvent(event)
            },
            onRequestTaskbarMenu: { [weak self] event, view in
                self?.onRequestTaskbarMenu?(event, view)
            }
        ).environmentObject(runtime).environmentObject(drawerStore).environmentObject(messagingStore).environmentObject(badgeStore).environmentObject(stripOrderStore).environmentObject(pinnedFolderStore).environmentObject(folderCoverStore).environmentObject(shelfStore).environmentObject(dragController).environmentObject(keptAppStore).environmentObject(runningApplicationStore).environmentObject(appMembershipController).environmentObject(settingsStore))
        hosting.autoresizingMask = [.width, .height]
        // Prevent NSHostingView from adding its own opaque background over the blur
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor
        dockContentHost = ManualPanelHost(contentView: hosting, in: panel)
        dockPanel = panel
    }

    private func moveExternalFiles(_ urls: [URL], into path: String) {
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        fileDropQueue.async {
            let eligible = FolderDropPlan.eligibleSources(urls, destination: destination)
            guard !eligible.isEmpty else { return }
            let result = FileMover().move(eligible, into: destination)
            guard result.hasIssues else { return }
            DispatchQueue.main.async { NSSound.beep() }
        }
    }

    private func setupCapsulePanel() {
        let panel = NonConstrainingPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: capsuleWidth + Self.shadowPadding * 2, height: capsuleWidth + Self.shadowPadding * 2)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 1.0, alpha: 0.0)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let hosting = NSHostingView(rootView:
            DrawerCapsuleButton(
                onRequestTaskbarMenu: { [weak self] event, view in
                    self?.onRequestTaskbarMenu?(event, view)
                },
                action: { [weak self] in self?.toggleDrawer() }
            )
                .environmentObject(runtime)
                .environmentObject(drawerStore)
                .environmentObject(messagingStore)
                .environmentObject(keptAppStore)
                .environmentObject(runningApplicationStore)
                .environmentObject(drawerOrderStore)
                .environmentObject(dragController)
                .environmentObject(settingsStore)
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.0).cgColor
        capsuleContentHost = ManualPanelHost(contentView: hosting, in: panel)
        capsulePanel = panel
    }

    /// 两个常驻面板先在隐藏态完成 SwiftUI 布局和目标 frame 提交，再一起显示。
    /// 这样首个可见 frame 已经是业务几何，不给 HostingView 的自然尺寸留下窗口级中间态。
    private func presentInitialPanels() {
        guard let dock = dockPanel, let capsule = capsulePanel else { return }
        dock.layoutIfNeeded()
        capsule.layoutIfNeeded()
        relayout(animated: false)
        dock.orderFrontRegardless()
        capsule.orderFrontRegardless()
    }

    // MARK: - Content Width via fittingSize

    private func subscribeSnapshotWidth() {
        snapshotWidthSubscription = runtime.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Defer one run-loop cycle so SwiftUI finishes layout before we read fittingSize
                DispatchQueue.main.async { [weak self] in
                    self?.relayout(animated: true)   // layoutPanels 内含抽屉重定位；转正期间 relayout 内部钳住宽度
                }
            }
    }

    private func subscribeDrawerStoreWidth() {
        drawerStoreWidthSubscription = drawerStore.$bundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.syncDrawerOrder()
                    self?.relayout(animated: true)
                }
            }
    }

    /// 跨面板拖动·"松手才变任务条长度"（owner 2026-06-22，各方向对称）：任一跨面板转换进行中
    /// （`DragController.conversion != nil`——进抽屉/出抽屉/消息区收纳/释放回消息区四向都算），把任务条
    /// 宽度**钳在拖动前的值**（`frozenDockContentWidth`，relayout 内部生效）——窗口卡照常出现/移出、
    /// 实时让位，但只是溢出或留空，面板**全程不变宽**。转换态结束（松手落定 / 拖出还原 → conversion 归 nil）
    /// 才解钳 + relayout，这一刻任务条才动画到最终长度。若全程没真正转换，结束时宽度=拖动前值，relayout 即无变化。
    private func subscribeConvertRelease() {
        convertReleaseSubscription = dragController.$conversion
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] converted in
                guard let self else { return }
                if converted {
                    // 转正开始：钳在"拖动前"宽度（此刻 lastDesiredWidth 仍是转正前的值，标志在改 drawerStore 前先置）。
                    if self.frozenDockContentWidth == nil { self.frozenDockContentWidth = self.lastDesiredWidth }
                } else {
                    self.frozenDockContentWidth = nil
                    // 换档事务里 cancelDrag() 也会走到这里排队一次带动画的布局；用代次吞掉它，
                    // 否则会先按新 metrics 动画一次、再被事务的无动画布局跳一次。
                    let generation = self.dockSizeChangeGeneration
                    DispatchQueue.main.async { [weak self] in
                        guard let self, generation == self.dockSizeChangeGeneration else { return }
                        self.relayout(animated: true)
                    }
                }
            }
    }

    /// 抽屉顺序按完整 placement 集合收敛，不按当前可见项裁。即便抽屉没开也同步，
    /// 让隐藏成员下一次启动时回到原来的相对位置。
    private func syncDrawerOrder() {
        let members = AppMembershipProjection.drawerMembers(drawerIDs: drawerStore.bundleIDs)
        drawerOrderStore.sync(members: members)
    }

    private func subscribeMessagingStoreWidth() {
        messagingStoreWidthSubscription = messagingStore.$bundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.relayout(animated: true)
                }
            }
    }

    private func subscribeKeptAppStore() {
        keptAppStoreSubscription = keptAppStore.$bundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.relayout(animated: true)
                }
            }
    }

    private func subscribeRunningApplicationStore() {
        runningApplicationStoreSubscription = runningApplicationStore.$runningBundleIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.relayout(animated: true) }
            }
    }

    private func subscribeSettings() {
        edgeDelaySubscription = settingsStore.$edgeAutoHideDelay
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcilePanelVisibility()
            }
        fullscreenIntentEnabledSubscription = settingsStore.$fullscreenIntentEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileFullscreenIntentMonitor()
            }
        // 中转格显隐会改变任务条内容宽度：只让 chip 消失不重排，面板会停在旧宽度，
        // 胶囊和打开着的抽屉也跟着停在旧位置。relayout 必须等 SwiftUI 这一轮布局跑完
        // （fittingSize 那时才是新值），所以再推一轮主队列。
        showShelfSubscription = settingsStore.$showShelf
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.folderPopupWantsOpen, self.openPopupContent == .shelf { self.closeFolderPopup() }
                DispatchQueue.main.async { [weak self] in self?.relayout(animated: true) }
            }
        dockSizeSubscription = settingsStore.$dockSize
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.beginDockSizeChange() }
    }

    /// 换档是一次**事务**，不是普通的内容变化：面板高度、胶囊宽度、条内每个 chip 的尺寸同时变，
    /// 中途任何一次动画布局都会把三个面板摆到半新半旧的几何上。
    ///
    /// 顺序是有讲究的：
    /// 1. 先收掉所有依附在旧几何上的东西——拖动载体（尺寸随档位）、抽屉（`maxContentHeight`
    ///    是开抽屉时一次性传进根视图的，只挪外框会裁掉内容）、弹窗与 tooltip（锚点已作废）。
    /// 2. `cancelDrag()` 会经 `subscribeConvertRelease` 排队一次**带动画**的 relayout，
    ///    用 generation 门控把它吞掉，否则先按新 metrics 动画一次、再瞬时跳一次。
    /// 3. 等 SwiftUI 用新档位跑完一轮布局（`fittingSize` 那时才是新宽度），再一次性无动画提交。
    ///    换档是瞬时的，不做过渡动画。
    ///
    /// 最大化避让不需要在这里做任何事：`taskbarTop` 由 `panelHeight` 算出、在 Equatable 的
    /// `WindowLiftAvoidanceContext` 里，档位一变 `reconcileContext` 就走既有的还原→重抬路径。
    private func beginDockSizeChange() {
        dockSizeChangeGeneration &+= 1
        let generation = dockSizeChangeGeneration

        dragController.cancelDrag()
        dismissWindowTitleTooltip()
        closeFolderPopup(immediately: true)
        if drawerWantsOpen { closeDrawer() }

        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.dockSizeChangeGeneration else { return }
            self.relayout(animated: false)
        }
    }

    // MARK: - 目标 frame 驱动布局
    //
    // Codex 二审根因：动画后若"读上一个面板正在动画的 live frame 来定位下一个"，读到的是动画起点的旧值
    // → 胶囊按旧任务条、抽屉按旧胶囊定位 → 任务条变宽后错位、抽屉与任务条重叠。修法：一次算齐三个**目标**
    // frame（纯函数,互不读 live frame），三面板在**同一个动画组**里各自滑向目标。

    private static let layoutAnimationDuration: TimeInterval = DrawerAnimation.duration

    /// 任务条目标 frame（按内容宽度、居中、限宽）。
    private func dockTargetFrame(contentWidth: CGFloat, on screen: NSScreen) -> NSRect {
        PanelGeometry.dockTargetFrame(contentWidth: contentWidth, on: Self.screenGeometry(screen), metrics: layoutMetrics)
    }

    /// 胶囊目标 frame（贴任务条右边、纵向居中）。只依赖传入的 dock **目标** frame。
    private func capsuleTargetFrame(forDock dockFrame: NSRect, on screen: NSScreen) -> NSRect {
        PanelGeometry.capsuleTargetFrame(forDock: dockFrame, on: Self.screenGeometry(screen), metrics: layoutMetrics)
    }

    /// 抽屉目标 frame（右边贴胶囊右边、**底边硬锚在胶囊上方、向上长**）。只依赖传入的胶囊 **目标** frame + 抽屉尺寸。
    /// 关键：底边绝不下移——超过上方可用空间就**封顶高度**（内容由 DrawerView 内部滚动），
    /// 绝不靠"把底边往下压"来塞下，否则压到胶囊/任务条（owner 2026-06-21 报图）。
    private func drawerTargetFrame(forCapsule capsuleFrame: NSRect, size: CGSize, on screen: NSScreen) -> NSRect {
        // 底部/左右定位使用 screen.frame，切断与原生 Dock visibleFrame 的耦合；
        // 顶部高度仍由 topUsableY 封顶，避免菜单栏和刘海遮挡。
        PanelGeometry.drawerTargetFrame(forCapsule: capsuleFrame, size: size, on: Self.screenGeometry(screen), metrics: layoutMetrics)
    }

    /// 统一布局入口：算齐三个目标 frame、存好（给 drop zone / 开抽屉读），三面板同组动画到目标。
    /// 开屏/切屏/多屏悬停传 animated:false；内容变化、收纳/移回、抽屉尺寸变化传 animated:true。
    private func layoutPanels(contentWidth: CGFloat, on screen: NSScreen, animated: Bool) {
        guard let dock = dockPanel, let capsule = capsulePanel else { return }
        let panelScreenCGFrame = Self.toCGRect(screen)
        fullscreenIntentMonitor?.updatePanelScreen(panelScreenCGFrame)
        if let transaction = fullscreenIntentTransaction,
           transaction.screenCGFrame != panelScreenCGFrame {
            cancelFullscreenIntent(generation: transaction.generation, reason: "panel-screen-changed")
        }
        let anim = animated && didInitialLayout   // 首帧瞬时,别从初始位置滑过来
        didInitialLayout = true

        let dockT = dockTargetFrame(contentWidth: contentWidth, on: screen)
        let capsuleT = capsuleTargetFrame(forDock: dockT, on: screen)
        // 任务条目标帧一变（宽度/切屏）就关弹窗——不追动画中的锚点（与原生 Dock 行为一致,保 target-frame 纯度）。
        if dockT != lastDockTargetFrame {
            if folderPopupWantsOpen { closeFolderPopup() }
            dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
        }
        lastDockTargetFrame = dockT
        lastCapsuleTargetFrame = capsuleT

        var pairs: [(NSPanel, NSRect)] = [(dock, dockT), (capsule, capsuleT)]
        if let drawer = drawerPanel, drawer.isVisible, let hosting = drawerContentHost {
            let fitting = hosting.fittingSize
            let drawerSize = CGSize(width: max(fitting.width, 60), height: max(fitting.height, 60))
            lastDrawerSize = drawerSize
            let drawerT = drawerTargetFrame(forCapsule: capsuleT, size: drawerSize, on: screen)
            lastDrawerTargetFrame = drawerT
            pairs.append((drawer, drawerT))
        }
        setFrames(pairs, animated: anim)
    }

    /// 量当前内容宽度后布局（内容变化的统一入口）。
    private func relayout(animated: Bool) {
        guard let panel = dockPanel, let hosting = dockContentHost else { return }
        let measured = hosting.fittingSize.width - 2 * Self.shadowPadding
        lastDesiredWidth = measured
        // 跨面板转正进行中 → 任务条宽度钳在拖动前的值（窗口卡溢出/留空而非改变面板宽度，owner 2026-06-22）；
        // 松手/还原解钳后，下一次 relayout 用真实测量值把任务条变到最终长度。
        let contentWidth = frozenDockContentWidth ?? measured
        layoutPanels(contentWidth: contentWidth, on: panelCurrentScreen(panel: panel), animated: animated)
    }

    /// 三面板同一个动画组提交,共用一条时间轴（Codex 二审 P2：避免各跑各的时间轴抖动）。
    private func setFrames(_ pairs: [(NSPanel, NSRect)], animated: Bool) {
        guard animated else { for (p, f) in pairs { p.setFrame(f, display: true) }; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.layoutAnimationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (p, f) in pairs { p.animator().setFrame(f, display: true) }
        }
    }

    @objc private func screenParametersChanged() {
        dragController?.cancelDrag()   // 切屏/分辨率变 → 取消进行中的跨面板拖动，免得载体留在旧屏坐标
        cancelHoverSwitch()
        closeFolderPopup()             // 屏幕参数变了,旧锚点坐标作废
        dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
        guard dockPanel != nil else { return }
        relayout(animated: false)      // 切屏瞬时,不滑
        cancelFullscreenIntentIfContextChanged()
        reconcilePanelVisibility()
    }

    // MARK: - Fullscreen Monitor

    private func setupFullscreenMonitor() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleSpaceChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleAppActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        lastActiveApplicationPID = NSWorkspace.shared.runningApplications.first(where: { $0.isActive })?.processIdentifier
        fullscreenReconcileTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fullscreenReconcileIfNeeded() }
        }
        fullscreenReconcileTimer?.tolerance = 0.5
    }

    private func reconcileFullscreenIntentMonitor() {
        let enabled = FullscreenIntentDecision.isEnabled(
            settingEnabled: settingsStore.fullscreenIntentEnabled,
            environment: ProcessInfo.processInfo.environment
        )
        guard enabled, !isSuspendedForPermissionLoss else {
            fullscreenIntentMonitor?.stop()
            fullscreenIntentMonitor = nil
            if let transaction = fullscreenIntentTransaction {
                cancelFullscreenIntent(generation: transaction.generation, reason: "disabled")
            }
            return
        }
        guard fullscreenIntentMonitor == nil else { return }
        let monitor = FullscreenIntentMonitor(
            onIntent: { [weak self] request in
                self?.beginFullscreenIntent(request)
            },
            onContextChange: { [weak self] change in
                self?.handleFullscreenIntentContextChange(change)
            }
        )
        fullscreenIntentMonitor = monitor
        monitor.updatePanelScreen(currentPanelScreenCGFrame())
        monitor.start()
    }

    @objc private func handleSpaceChange() {
        // Sync CG check: fires before the panel has a chance to appear, no AX = no main-thread risk
        let cgFullscreen = checkFullscreenViaCGSync()
        applyFullscreenVisibility(
            cgFullscreen,
            source: "space-cg",
            expectedIntentGeneration: fullscreenIntentTransaction?.generation,
            pid: lastActiveApplicationPID,
            screenCGFrame: currentPanelScreenCGFrame()
        )
        // Async AX secondary check: catches edge cases CG misses (e.g. games on a non-zero layer)
        if !cgFullscreen || fullscreenIntentTransaction == nil { triggerAsyncFullscreenCheck() }
    }

    @objc private func handleAppActivated(_ note: Notification) {
        // 用通知携带的"刚激活的 app"，不读滞后的 frontmostApplication（AGENTS 守则）
        let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        lastActiveApplicationPID = activated?.processIdentifier
        cancelFullscreenIntentIfContextChanged(activePID: activated?.processIdentifier)
        triggerAsyncFullscreenCheck(pid: lastActiveApplicationPID)
    }

    // MARK: - Sync CG fullscreen probe (main thread only, no AX)

    private func checkFullscreenViaCGSync() -> Bool {
        guard let panel = dockPanel else { return false }
        let screen = panelCurrentScreen(panel: panel)
        let screenCGFrame = Self.toCGRect(screen)
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let candidate = WindowLiftCGWindowProbe.frontmostLargeWindow(
            on: screenCGFrame,
            excludingPID: ourPID
        ) else { return false }

        let cgBounds = candidate.quartzFrame
        let t: CGFloat = 8
        return abs(cgBounds.width  - screenCGFrame.width)  < t
            && abs(cgBounds.height - screenCGFrame.height) < t
            && abs(cgBounds.minX   - screenCGFrame.minX)   < t
            && abs(cgBounds.minY   - screenCGFrame.minY)   < t
    }

    // MARK: - Async AX fullscreen probe (secondary / fallback)

    private func triggerAsyncFullscreenCheck(pid explicitPID: pid_t? = nil) {
        guard let panel = dockPanel else { return }
        // Convert to CG coords on main thread; AX kAXPositionAttribute also uses CG (top-left origin)
        let screenCGFrame = Self.toCGRect(panelCurrentScreen(panel: panel))
        let frontPID = explicitPID ?? lastActiveApplicationPID
        fullscreenProbeGeneration &+= 1
        let probeGeneration = fullscreenProbeGeneration
        let expectedIntentGeneration = fullscreenIntentTransaction?.generation
        Task.detached { [weak self] in
            let fullscreen = Self.detectFullscreenViaAX(pid: frontPID, screenCGFrame: screenCGFrame)
            await MainActor.run { [weak self] in
                guard let self,
                      probeGeneration == self.fullscreenProbeGeneration else {
                    return
                }
                self.applyFullscreenVisibility(
                    fullscreen,
                    source: "ax",
                    expectedIntentGeneration: expectedIntentGeneration,
                    pid: frontPID,
                    screenCGFrame: screenCGFrame
                )
            }
        }
    }

    private func fullscreenReconcileIfNeeded() {
        guard visibilityState.hideReasons.contains(.fullscreen) else { return }
        triggerAsyncFullscreenCheck()
    }

    private func applyFullscreenVisibility(
        _ isFullscreen: Bool,
        source: String,
        expectedIntentGeneration: UInt64? = nil,
        pid: pid_t? = nil,
        screenCGFrame: CGRect? = nil
    ) {
        if isFullscreen {
            if let transaction = fullscreenIntentTransaction {
                guard expectedIntentGeneration == transaction.generation,
                      pid == transaction.pid,
                      screenCGFrame == transaction.screenCGFrame,
                      isFullscreenIntentContextCurrent(transaction),
                      visibilityState.confirmFullscreenTransition(generation: transaction.generation) else {
                    return
                }
                finishFullscreenIntentTransaction()
                fullscreenIntentLogger.notice(
                    "confirmed source=\(source, privacy: .public) generation=\(transaction.generation, privacy: .public)"
                )
            } else {
                visibilityState.setFullscreen(true)
            }
            closeDrawer()
            closeFolderPopup()
            dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
        } else {
            if fullscreenIntentTransaction != nil { return }
            visibilityState.setFullscreen(false)
        }
        reconcilePanelVisibility()
        logger.info("[fullscreen] active=\(isFullscreen, privacy: .public)")
    }

    private func beginFullscreenIntent(_ request: FullscreenIntentRequest) {
        guard fullscreenIntentMonitor != nil,
              fullscreenIntentTransaction == nil,
              request.screenCGFrame == currentPanelScreenCGFrame(),
              lastActiveApplicationPID == request.pid else {
            return
        }
        fullscreenIntentGeneration &+= 1
        let generation = fullscreenIntentGeneration
        fullscreenProbeGeneration &+= 1
        fullscreenIntentTransaction = FullscreenIntentTransaction(
            generation: generation,
            pid: request.pid,
            focusedWindowID: request.focusedWindowID,
            screenCGFrame: request.screenCGFrame
        )
        fullscreenIntentTimeoutTimer?.invalidate()
        visibilityState.beginFullscreenTransition(generation: generation)

        edgeIdleHideTimer?.invalidate()
        edgeIdleHideTimer = nil
        cancelEdgeWake()

        dragController?.cancelDrag()
        closeDrawerImmediately()
        closeFolderPopup(immediately: true)
        dismissWindowTitleTooltip(suppressCurrentUntilExit: true)

        panelsAreVisible = false
        dockPanel?.orderOut(nil)
        capsulePanel?.orderOut(nil)
        drawerPanel?.orderOut(nil)
        folderPopupPanel?.orderOut(nil)
        windowTitleTooltipPanel?.orderOut(nil)
        fullscreenIntentLogger.notice(
            "pending source=\(request.source.rawValue, privacy: .public) generation=\(generation, privacy: .public) pid=\(request.pid, privacy: .public)"
        )

        let timer = Timer(timeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelFullscreenIntent(generation: generation, reason: "timeout")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullscreenIntentTimeoutTimer = timer

        DispatchQueue.main.async { [weak self] in
            guard let self, self.fullscreenIntentTransaction?.generation == generation else { return }
            self.reconcilePanelVisibility()
        }
    }

    private func cancelFullscreenIntent(generation: UInt64, reason: String) {
        guard fullscreenIntentTransaction?.generation == generation,
              visibilityState.timeoutFullscreenTransition(generation: generation) else {
            return
        }
        finishFullscreenIntentTransaction()
        fullscreenProbeGeneration &+= 1
        fullscreenIntentLogger.notice(
            "cancelled reason=\(reason, privacy: .public) generation=\(generation, privacy: .public)"
        )
        reconcilePanelVisibility()
    }

    private func finishFullscreenIntentTransaction() {
        fullscreenIntentTransaction = nil
        fullscreenIntentTimeoutTimer?.invalidate()
        fullscreenIntentTimeoutTimer = nil
    }

    private func cancelFullscreenIntentIfContextChanged(activePID: pid_t? = nil) {
        guard let transaction = fullscreenIntentTransaction else { return }
        let currentPID = activePID ?? lastActiveApplicationPID
        guard currentPID != transaction.pid || currentPanelScreenCGFrame() != transaction.screenCGFrame else {
            return
        }
        cancelFullscreenIntent(generation: transaction.generation, reason: "context-changed")
    }

    private func isFullscreenIntentContextCurrent(_ transaction: FullscreenIntentTransaction) -> Bool {
        NSRunningApplication(processIdentifier: transaction.pid)?.isActive == true
            && currentPanelScreenCGFrame() == transaction.screenCGFrame
    }

    private func handleFullscreenIntentContextChange(
        _ change: FullscreenIntentMonitor.ContextChange
    ) {
        if case let .activeApplication(pid) = change {
            lastActiveApplicationPID = pid
        }
        guard let transaction = fullscreenIntentTransaction else { return }
        switch change {
        case let .activeApplication(pid):
            if pid != transaction.pid {
                cancelFullscreenIntent(generation: transaction.generation, reason: "app-changed")
            }
        case .focusedWindow:
            cancelFullscreenIntent(generation: transaction.generation, reason: "focus-changed")
        case let .windowDestroyed(windowID):
            if windowID == nil || windowID == transaction.focusedWindowID {
                cancelFullscreenIntent(generation: transaction.generation, reason: "window-destroyed")
            }
        }
    }

    private func currentPanelScreenCGFrame() -> CGRect? {
        guard let panel = dockPanel else { return nil }
        return Self.toCGRect(panelCurrentScreen(panel: panel))
    }

    private func panelCurrentScreen(panel: NSPanel) -> NSScreen {
        // Use the center of the visible content area (inset by shadowPadding) so the 12pt shadow
        // bleed below screen.frame.minY doesn't cause first(where:intersects) to return the wrong
        // adjacent screen in multi-monitor setups (e.g. vertically stacked 3-screen layouts).
        let visualCenter = CGPoint(
            x: panel.frame.midX,
            y: panel.frame.minY + Self.shadowPadding + panelHeight / 2
        )
        return NSScreen.screens.first(where: { $0.frame.contains(visualCenter) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // AppKit frame (bottom-left origin) → CG/Quartz frame (top-left origin of primary screen)
    private static func toCGRect(_ screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(
            x: f.minX,
            y: quartzPrimaryScreenHeight - f.maxY,
            width: f.width,
            height: f.height
        )
    }

    /// `NSScreen.main` follows the key window and may be a secondary display. Quartz global
    /// coordinates are anchored to the menu-bar display, which is always the first screen.
    private static var quartzPrimaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
    }

    nonisolated private static func detectFullscreenViaAX(pid: pid_t?, screenCGFrame: CGRect) -> Bool {
        guard let pid else { return false }
        let reader = AXWindowReader()
        let appElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(appElement, 0.5)

        guard let focused = reader.elementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) else {
            return false
        }
        _ = AXUIElementSetMessagingTimeout(focused, 0.5)

        let role = reader.stringAttribute(kAXRoleAttribute as CFString, from: focused, maxAttempts: 1)
        let isAXFullscreen = reader.boolAttribute("AXFullScreen" as CFString, from: focused, maxAttempts: 1) ?? false
        // AX kAXPositionAttribute uses CG coordinates (top-left origin) — matches screenCGFrame directly
        let windowFrame = reader.frame(of: focused, maxAttempts: 1)

        return FullscreenWindowClassifier.isFullscreen(
            role: role,
            isAXFullscreen: isAXFullscreen,
            windowFrame: windowFrame,
            screenCGFrame: screenCGFrame
        )
    }

    // MARK: - HoverSwitch Diagnostics

    private let hoverLogger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "HoverSwitch")
    private static let hoverHotZone: CGFloat = 4.0
    private static let hoverSwitchDwell: TimeInterval = 0.35   // 光标驻留热区 ≥ 350ms 才切换，路过不算
    private static let hoverVerboseLogging = false
    /// 底边唤醒/自动隐藏的复现诊断（owner 2026-07-16 issue #2 排查）。默认关闭；这里用纯 print()
    /// 而不是 Logger/os_log——沙箱环境读不了 `log show`/`log stream`，只有落到重定向文件里的
    /// print() 能直接读回。AppDelegate 已对 stdout 做行缓冲（`setvbuf(stdout, nil, _IOLBF, 0)`），
    /// 这里不需要额外处理缓冲。
    private static let edgeHoverTraceEnabled = ProcessInfo.processInfo.environment["DOCK_EDGEHOVER_TRACE"] == "1"
    /// 菜单跟踪深度（子菜单会嵌套），0 = 当前没有菜单在跟踪。
    private var menuTrackingDepth = 0
    private static let menuHoverSuspensionEnabled = ProcessInfo.processInfo.environment["DOCK_MENU_HOVER_SUSPEND"] != "0"
    private var hoverLastScreenIndex: Int? = nil
    private var hoverLastInHotZone: Bool? = nil
    private var hoverSwitchTimer: Timer?
    private var hoverSwitchTargetScreen: NSScreen? = nil

    private func setupHoverDiagnostics() {
        if Self.hoverVerboseLogging { logScreenMap() }
        installHoverMouseMonitors()
        observeMenuTrackingForHoverSuspension()
        pollMousePosition()
    }

    /// **菜单跟踪期间摘掉鼠标移动监视器**（owner 2026-08-04 报「菜单里两个选项之间来回晃有粘滞感」，
    /// 状态栏菜单 / 任务条右键 / 图标右键三处都一样，而这三者唯一的共同点就是"由钨极弹出"）。
    ///
    /// `addGlobalMonitorForEvents` 在系统底层是一个事件拦截器，所有鼠标事件都要先过它。平时主循环
    /// 在普通模式，它随到随处理，**所以别的应用的菜单不受影响**；但钨极自己弹菜单时主循环切进
    /// 事件跟踪模式，这个拦截器的处理入口在该模式下不被服务，每个鼠标移动事件都要在拦截器里
    /// 等到超时才继续送达——菜单高亮因此慢半拍。实测佐证：菜单开着时主线程 93% 阻塞在
    /// `mach_msg2_trap` 干等事件，我们自己的代码 0 个采样，所以不是"没空处理"，是"事件来得晚"。
    ///
    /// 用 `NSMenu` 的应用级跟踪通知，一处覆盖全部菜单（chip 菜单是现搭的，没有别的公共钩子）。
    /// 子菜单会让通知嵌套，所以按深度计数而不是布尔值。
    /// 关掉这个优化：`DOCK_MENU_HOVER_SUSPEND=0`。
    private func observeMenuTrackingForHoverSuspension() {
        guard Self.menuHoverSuspensionEnabled else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    @objc private func menuTrackingDidBegin() {
        menuTrackingDepth += 1
        guard menuTrackingDepth == 1 else { return }
        suspendHoverMouseMonitors()
    }

    @objc private func menuTrackingDidEnd() {
        menuTrackingDepth = max(0, menuTrackingDepth - 1)
        guard menuTrackingDepth == 0 else { return }
        installHoverMouseMonitors()
        // 摘掉的这段时间里鼠标可能已经跨屏或离开了底边热区，装回来立刻补一次判断，
        // 否则要等下一次鼠标移动才纠正。
        pollMousePosition()
    }

    /// 只摘监视器，**不碰**唤醒/切屏状态——那些由 `removeHoverMouseMonitors` 在真正拆除时负责。
    /// 菜单开着的这一两秒里把 `cancelEdgeWake()` 一起做掉的话，隐藏状态下打开状态栏菜单
    /// 会顺手取消掉正在武装的底边唤醒，属于额外的行为改动。
    private func suspendHoverMouseMonitors() {
        if let monitor = hoverLocalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            hoverLocalMouseMonitor = nil
        }
        if let monitor = hoverGlobalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            hoverGlobalMouseMonitor = nil
        }
    }

    private func installHoverMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if hoverLocalMouseMonitor == nil {
            hoverLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                Task { @MainActor [weak self] in self?.pollMousePosition() }
                return event
            }
        }
        if hoverGlobalMouseMonitor == nil {
            hoverGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pollMousePosition() }
            }
        }
    }

    private func removeHoverMouseMonitors() {
        if let monitor = hoverLocalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            hoverLocalMouseMonitor = nil
        }
        if let monitor = hoverGlobalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            hoverGlobalMouseMonitor = nil
        }
        cancelHoverSwitch()
        cancelEdgeWake()
    }

    private func logScreenMap() {
        let screens = NSScreen.screens
        for (i, screen) in screens.enumerated() {
            let f = screen.frame
            let vf = screen.visibleFrame
            hoverLogger.info("screen-map index=\(i, privacy: .public) name=\(screen.localizedName, privacy: .public) frame=(\(f.minX, privacy: .public),\(f.minY, privacy: .public),\(f.width, privacy: .public),\(f.height, privacy: .public)) visibleFrame=(\(vf.minX, privacy: .public),\(vf.minY, privacy: .public),\(vf.width, privacy: .public),\(vf.height, privacy: .public)) isMain=\(screen == NSScreen.main, privacy: .public) isScreens0=\(i == 0, privacy: .public)")
        }
    }

    private func pollMousePosition() {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens

        var curScreenIdx: Int? = nil
        var curScreen: NSScreen? = nil
        for (i, s) in screens.enumerated() {
            if s.frame.contains(mouse) { curScreenIdx = i; curScreen = s; break }
        }

        let dyFromBottom: CGFloat
        let inHotZone: Bool
        if let s = curScreen {
            dyFromBottom = mouse.y - s.frame.minY
            inHotZone = dyFromBottom <= Self.hoverHotZone
        } else {
            dyFromBottom = -1
            inHotZone = false
        }

        handleBottomEdgeProbe(screen: curScreen, inHotZone: inHotZone)
        updateEdgeIdleTimerFromMouse()

        guard curScreenIdx != hoverLastScreenIndex || inHotZone != hoverLastInHotZone else { return }
        hoverLastScreenIndex = curScreenIdx
        hoverLastInHotZone = inHotZone

        if Self.hoverVerboseLogging {
            let panelScreenIdx = dockPanel.map { p -> String in
                let ps = panelCurrentScreen(panel: p)
                return screens.firstIndex(of: ps).map { "\($0)" } ?? "?"
            } ?? "nil"
            if let s = curScreen, let idx = curScreenIdx {
                let f = s.frame
                let vf = s.visibleFrame
                hoverLogger.info("cursor screen=\(idx, privacy: .public) name=\(s.localizedName, privacy: .public) mouse=(\(mouse.x, privacy: .public),\(mouse.y, privacy: .public)) frame=(\(f.minX, privacy: .public),\(f.minY, privacy: .public),\(f.width, privacy: .public),\(f.height, privacy: .public)) visibleFrame=(\(vf.minX, privacy: .public),\(vf.minY, privacy: .public),\(vf.width, privacy: .public),\(vf.height, privacy: .public)) dyFromBottom=\(dyFromBottom, privacy: .public) inHotZone=\(inHotZone, privacy: .public) panelScreen=\(panelScreenIdx, privacy: .public)")
            } else {
                hoverLogger.info("cursor screen=none mouse=(\(mouse.x, privacy: .public),\(mouse.y, privacy: .public)) dyFromBottom=none inHotZone=false panelScreen=\(panelScreenIdx, privacy: .public)")
            }
        }

    }

    private func cancelHoverSwitch() {
        hoverSwitchTimer?.invalidate()
        hoverSwitchTimer = nil
        hoverSwitchTargetScreen = nil
    }

    private func commitHoverSwitch() {
        hoverSwitchTimer = nil
        guard let targetScreen = hoverSwitchTargetScreen, let panel = dockPanel else {
            hoverSwitchTargetScreen = nil
            return
        }
        hoverSwitchTargetScreen = nil
        // Confirm the cursor is still on the target screen (it may have left within the last poll gap).
        guard targetScreen.frame.contains(NSEvent.mouseLocation) else { return }
        let panelScreen = panelCurrentScreen(panel: panel)
        guard targetScreen != panelScreen else { return }   // panel already moved (e.g. screenParametersChanged)
        let screens = NSScreen.screens
        let fromIdx = screens.firstIndex(of: panelScreen).map { "\($0)" } ?? "?"
        let toIdx = screens.firstIndex(of: targetScreen).map { "\($0)" } ?? "?"
        let actualWidth = PanelGeometry.dockTargetFrame(
            contentWidth: lastDesiredWidth,
            on: Self.screenGeometry(targetScreen),
            metrics: layoutMetrics
        ).width - Self.shadowPadding * 2
        closeFolderPopup()   // 切屏后旧锚点在旧屏,弹窗收起
        dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
        layoutPanels(contentWidth: lastDesiredWidth, on: targetScreen, animated: false)
        hoverLogger.info("switch toScreen=\(toIdx, privacy: .public) name=\(targetScreen.localizedName, privacy: .public) actualWidth=\(actualWidth, privacy: .public) fromScreen=\(fromIdx, privacy: .public)")
        armEdgeWakeIfNeeded(on: targetScreen, requiresHotZone: false)
    }

    private func handleBottomEdgeProbe(screen: NSScreen?, inHotZone: Bool) {
        guard let screen, let panel = dockPanel else {
            cancelHoverSwitch()
            cancelEdgeWake()
            return
        }

        let panelScreen = panelCurrentScreen(panel: panel)
        if screen != panelScreen {
            cancelEdgeWake()
            if hoverSwitchTargetScreen == screen {
                return
            }
            if inHotZone {
                hoverSwitchTimer?.invalidate()
                hoverSwitchTargetScreen = screen
                let timer = Timer(timeInterval: Self.hoverSwitchDwell, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.commitHoverSwitch() }
                }
                RunLoop.main.add(timer, forMode: .common)
                hoverSwitchTimer = timer
            } else {
                cancelHoverSwitch()
            }
            return
        }

        cancelHoverSwitch()
        if inHotZone {
            armEdgeWakeIfNeeded(on: screen)
        } else if edgeWakeTargetScreen == screen, edgeWakeRequiresHotZone {
            cancelEdgeWake()
        }
    }

    /// 钨极菜单开着时停掉边缘自动隐藏，否则空闲计时照跑、任务条会从菜单底下缩掉。
    func setTaskbarMenuOpen(_ open: Bool) {
        setAutoHideInhibitor(.taskbarMenuOpen, active: open)
    }

    private func setAutoHideInhibitor(_ inhibitor: EdgeAutoHideInhibitor, active: Bool) {
        let before = visibilityState
        visibilityState.setInhibitor(inhibitor, active: active)
        if visibilityState != before { reconcilePanelVisibility() }
    }

    private func reconcilePanelVisibility() {
        edgeIdleHideTimer?.invalidate()
        edgeIdleHideTimer = nil

        let edgeDelay = settingsStore.edgeAutoHideDelay
        let edgeEnabled = edgeDelay != AppSettingsStore.neverHideDelay
        visibilityState.reconcileEdgeAutoHide(isEnabled: edgeEnabled)

        if edgeDelay == AppSettingsStore.neverHideDelay {
            cancelEdgeWake()
        } else if visibilityState.autoHideInhibitors.isEmpty,
                  !visibilityState.hideReasons.contains(.fullscreen),
                  !visibilityState.hideReasons.contains(.fullscreenTransitionPending) {
            if visibilityState.hideReasons.contains(.edgeAutoHide) {
                if EdgeAutoHideRuntimeRules.canArmWake(state: visibilityState, delay: edgeDelay),
                   let screen = screenContainingMouse(),
                   isMouseInBottomHotZone(on: screen) {
                    armEdgeWakeIfNeeded(on: screen)
                }
            } else if EdgeAutoHideRuntimeRules.canArmIdleHide(state: visibilityState, delay: edgeDelay),
                      isMouseOutsideInteractivePanels() {
                armEdgeIdleHideTimer()
            }
        } else {
            cancelEdgeWake()
        }

        applyPanelVisibility()
    }

    private func updateEdgeIdleTimerFromMouse() {
        guard EdgeAutoHideRuntimeRules.canArmIdleHide(state: visibilityState, delay: settingsStore.edgeAutoHideDelay) else { return }

        if isMouseOutsideInteractivePanels() {
            if edgeIdleHideTimer == nil {
                armEdgeIdleHideTimer()
            }
        } else {
            edgeIdleHideTimer?.invalidate()
            edgeIdleHideTimer = nil
        }
    }

    private func armEdgeIdleHideTimer() {
        guard let interval = EdgeAutoHideRuntimeRules.idleHideInterval(for: settingsStore.edgeAutoHideDelay) else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.edgeIdleHideTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeIdleHideTimer = timer
    }

    private func edgeIdleHideTimerFired() {
        edgeIdleHideTimer = nil
        guard EdgeAutoHideRuntimeRules.canArmIdleHide(state: visibilityState, delay: settingsStore.edgeAutoHideDelay),
              isMouseOutsideInteractivePanels() else { return }
        visibilityState.setEdgeAutoHidden(true)
        reconcilePanelVisibility()
    }

    private func armEdgeWakeIfNeeded(on screen: NSScreen, requiresHotZone: Bool = true) {
        guard EdgeAutoHideRuntimeRules.canArmWake(state: visibilityState, delay: settingsStore.edgeAutoHideDelay) else { return }
        if edgeWakeTargetScreen == screen,
           edgeWakeTimer != nil,
           edgeWakeRequiresHotZone == requiresHotZone { return }
        cancelEdgeWake()
        edgeWakeTargetScreen = screen
        edgeWakeRequiresHotZone = requiresHotZone
        let timer = Timer(timeInterval: settingsStore.edgeAutoHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.edgeWakeTimerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeWakeTimer = timer
    }

    private func edgeWakeTimerFired() {
        edgeWakeTimer = nil
        guard let screen = edgeWakeTargetScreen,
              edgeWakeShouldStillFire(on: screen),
              EdgeAutoHideRuntimeRules.canArmWake(state: visibilityState, delay: settingsStore.edgeAutoHideDelay) else {
            edgeWakeTargetScreen = nil
            edgeWakeRequiresHotZone = true
            return
        }
        edgeWakeTargetScreen = nil
        edgeWakeRequiresHotZone = true
        if let panel = dockPanel, panelCurrentScreen(panel: panel) != screen {
            layoutPanels(contentWidth: lastDesiredWidth, on: screen, animated: false)
        }
        visibilityState.setEdgeAutoHidden(false)
        reconcilePanelVisibility()
    }

    private func cancelEdgeWake() {
        edgeWakeTimer?.invalidate()
        edgeWakeTimer = nil
        edgeWakeTargetScreen = nil
        edgeWakeRequiresHotZone = true
    }

    private func edgeWakeShouldStillFire(on screen: NSScreen) -> Bool {
        if edgeWakeRequiresHotZone {
            return isMouseInBottomHotZone(on: screen)
        }
        return screen.frame.contains(NSEvent.mouseLocation)
    }

    private func applyPanelVisibility() {
        guard !isSuspendedForPermissionLoss else { return }
        let shouldShow = visibilityState.isVisible
        guard shouldShow != panelsAreVisible else { return }
        panelsAreVisible = shouldShow
        if Self.edgeHoverTraceEnabled { logEdgeHoverTrace(shouldShow: shouldShow) }
        if shouldShow {
            dockPanel?.orderFrontRegardless()
            capsulePanel?.orderFrontRegardless()
            if drawerWantsOpen { drawerPanel?.orderFrontRegardless() }
        } else {
            if visibilityState.hideReasons.contains(.fullscreen) { closeDrawer() }
            closeFolderPopup()
            dismissWindowTitleTooltip(suppressCurrentUntilExit: true)
            dockPanel?.orderOut(nil)
            capsulePanel?.orderOut(nil)
        }
    }

    /// `DOCK_EDGEHOVER_TRACE=1` 时每次实际 SHOW/HIDE 切换打一行：单调时钟（`CACurrentMediaTime`，
    /// 不受墙钟调整影响，用于量切换间隔）+ 鼠标坐标 + 是否在底边热区 + 是否在任务条/胶囊矩形内 +
    /// 当前唤醒延迟设置——足够从这一行日志本身看出"为什么"切换，而不只是"切换了"。
    private func logEdgeHoverTrace(shouldShow: Bool) {
        let mouse = NSEvent.mouseLocation
        let inHotZone = dockPanel.map { isMouseInBottomHotZone(on: panelCurrentScreen(panel: $0)) } ?? false
        let inPanelRect = (dockPanel?.frame.contains(mouse) ?? false) || (capsulePanel?.frame.contains(mouse) ?? false)
        print(String(
            format: "[edgehover] %@ t=%.4f mouse=(%.1f,%.1f) hotZone=%@ panelRect=%@ delay=%.2f reasons=%@",
            shouldShow ? "SHOW" : "HIDE",
            CACurrentMediaTime(),
            mouse.x, mouse.y,
            inHotZone ? "1" : "0",
            inPanelRect ? "1" : "0",
            settingsStore.edgeAutoHideDelay,
            "\(visibilityState.hideReasons)"
        ))
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func isMouseInBottomHotZone(on screen: NSScreen) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard screen.frame.contains(mouse) else { return false }
        return mouse.y - screen.frame.minY <= Self.hoverHotZone
    }

    private func isMouseOutsideInteractivePanels() -> Bool {
        let mouse = NSEvent.mouseLocation
        if let dock = dockPanel, dock.frame.contains(mouse) { return false }
        if let capsule = capsulePanel, capsule.frame.contains(mouse) { return false }
        if drawerWantsOpen, let drawer = drawerPanel, drawer.frame.contains(mouse) { return false }
        if folderPopupWantsOpen, let popup = folderPopupPanel, popup.frame.contains(mouse) { return false }
        // 唤醒热区贯穿整条屏幕底边，比居中的任务条/胶囊窄矩形宽得多；停在热区内但任务条范围外
        // 若判"已离开"会立刻武装 idle-hide，与刚触发的唤醒反复打架（唤醒→隐藏→唤醒…闪烁）。
        // 只在有限唤醒延迟下才压住——999/-1 两种模式没有这种打架，不该额外改变行为（见规则注释）。
        if EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: settingsStore.edgeAutoHideDelay),
           let dock = dockPanel, isMouseInBottomHotZone(on: panelCurrentScreen(panel: dock)) {
            return false
        }
        return true
    }

    // MARK: - Frame Helpers

    // 这两个不随档位缩放，保持静态常量。
    private static let outerMargin: CGFloat = PanelLayoutMetrics.tungstenEdge.outerMargin
    private static let capsuleGap: CGFloat = PanelLayoutMetrics.tungstenEdge.capsuleGap

    private static func screenGeometry(_ screen: NSScreen) -> PanelScreenGeometry {
        PanelScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top)
    }
}

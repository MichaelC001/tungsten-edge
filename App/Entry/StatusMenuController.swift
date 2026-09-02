import AppKit
import Combine

private enum StatusMenuLayout {
    static let textInsetX: CGFloat = 28
    static let trailingInsetX: CGFloat = 14
}

/// 系统 Dock 滑块的草稿账本。记着**改动前**的值，但只用来判「到底变没变」——
/// 写入失败时回滚到哪一档，由 `SettingsCoordinator.applyNativeDock` 自己重读系统真值决定
/// （界面手里的起点在草稿摊着的那段时间里可能已被 ⌥⌘D 改掉，见那里的注释）。
///
/// 提交源只有确认行一个（滑块本身不自动写系统），`consume()` 的**原子**语义是关键：
/// 它同时承担「值没变就不写」「没有起点就不写」两道闸，重复调用一律拿到 nil。
struct PreferenceSliderCommitTracker {
    private var baseline: Double?
    private var pending: Double?

    var hasPending: Bool { pending != nil }

    /// 记录草稿起点。一轮调整里只认第一次，中途重复调用不覆盖（拖动过程中会反复触发）。
    mutating func begin(currentDelay: Double) {
        if baseline == nil { baseline = currentDelay }
    }

    mutating func stage(_ value: Double) {
        pending = value
    }

    /// 原子取出待提交值。无起点、无变化、或已被别人消费过 → nil。
    mutating func consume() -> (previous: Double, target: Double)? {
        defer {
            baseline = nil
            pending = nil
        }
        guard let baseline, let pending, baseline != pending else { return nil }
        return (baseline, pending)
    }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let store: AppSettingsStore
    private let settingsCoordinator: SettingsCoordinator
    // 闭包注入而非直接依赖 PermissionService：测试 target 编译本文件但不含 PermissionService.swift。
    private let isAccessibilityTrusted: () -> Bool
    private let onShowDebugConsole: () -> Void
    private let onExportDebugSnapshot: () -> Void
    private let onShowSettings: () -> Void
    /// 菜单开 / 关。任务条的边缘自动隐藏要在菜单开着时停摆，否则空闲计时照跑，
    /// 任务条会从弹出的菜单底下缩掉（同 `folderPopupOpen`）。走闭包是因为
    /// `PanelCoordinator` 在权限引导完成前根本不存在。
    private let onMenuVisibilityChanged: (Bool) -> Void
    private let onQuit: () -> Void
    /// 当前显隐快捷键的展示字形。走闭包现取：用户改键后组标题要在下次打开时跟着变。
    private let hotKeyGlyphs: () -> String
    // 闭包注入：注册状态归 AppDelegate 持有的 GlobalHotKeyMonitor，菜单每次刷新时现查。
    private let isToggleHotKeyRegistered: () -> Bool
    /// 在场屏快照的来源。闭包注入而非直接调 `DisplayIdentity`：测试 target 编译本文件
    /// 但不含 `Platform/`（同 `isAccessibilityTrusted` 的理由）。
    private let connectedScreens: () -> [(uuid: String, title: String)]
    /// 屏幕快照缓存。**菜单路径只读它，绝不现算**——`localizedName` 会读 IODisplay，
    /// 菜单路径上的主线程系统 I/O 会让 macOS 合并 mouse-moved 事件（菜单划不动）。
    private var connectedScreensCache: [(uuid: String, title: String)] = []
    private var screenParametersObserver: NSObjectProtocol?
    private var edgeDelaySubscription: AnyCancellable?
    /// 待装新版的提示：图标上那个点要在菜单关着时也能亮起来，所以单独订阅。
    private var pendingUpdateSubscription: AnyCancellable?
    private var systemTruthRefreshTask: Task<Void, Never>?
    private var isMenuOpen = false
    private var isPreparedForTaskbarPresentation = false
    /// 本次菜单是不是从任务条右键弹出来的。菜单锚在任务条上沿，任务条一缩它就悬空了，
    /// 所以这条路径下**不做实时预览**（owner 2026-08-03）；状态栏图标那条不受影响。
    private var isPresentedFromTaskbar = false

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let permissionWarningItem = NSMenuItem(title: String(localized: "Accessibility Permission Required"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let permissionWarningSeparator = NSMenuItem.separator()
    private let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
    /// 登录项 2026-08-24 当天两度搬家：随菜单去重挪去设置窗口，owner 复议后**回到菜单做第一项**、
    /// 设置窗口不再放（仍不重复）。别再挪回设置窗口，除非 owner 再开口。
    private let launchAtLoginItem = NSMenuItem(title: String(localized: "Open at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openLoginItemsSettingsItem = NSMenuItem(title: String(localized: "Open Login Items Settings…"), action: #selector(openLoginItemsSettings), keyEquivalent: "")
    /// 「安装 vX.Y.Z…」：**只在有待装新版时可见**（2026-08-24 菜单去重）。登录项、检查更新、
    /// 版本号都只住设置窗口了；这一行是菜单里唯一的更新表面，因为它是一条**消息**不是命令——
    /// 红点要在用户没主动去查的时候也能被看见。可见性只允许在 `prepareMenuForPresentation`
    /// 翻转（菜单开着时增删行会让任务条锚点漂移，见 refreshInstallUpdateItem）。
    private let installUpdateItem = NSMenuItem(title: "", action: #selector(installPendingUpdate), keyEquivalent: "")
    /// 钨极组的分组标题，恒不可点（title 在 refreshEdgeSectionTitle 里随热键注册状态落）。
    private let edgeSectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    // 中转站 / 悬停显示应用名 / 最大化避让 / 任务条大小 2026-09-01 从设置窗口搬回菜单
    // （owner 拍板，反转 2026-08-03 的分工）：它们是调外观时随手要切的，为此开一次窗不值。
    // 四项并进钨极组（不另起帽子），与「钨极 Dock 栏显示在 ▸」同组。
    // 登录项 / 检查更新 / 版本号仍按 2026-08-24 的去重结果：只在设置窗口。

    /// 分组标题，恒不可点（title 在 configureMenu 里落）。
    private let nativeDockSectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// 滑块草稿的唯一提交入口，默认隐藏。承载的是**真按钮**而不是普通菜单文字行：
    /// 做成菜单行时它和邻居（「打开系统 Dock 设置…」）视觉权重一样，混在菜单里不显眼，
    /// 而用户刚拖完滑块视线还在滑块上，错过它就从「会闪但生效了」变成
    /// 「以为设好了其实没生效」——比原来的闪更糟（owner 2026-08-02 验收时指出）。
    private let nativeDockApplyItem = NSMenuItem()
    private let nativeDockApplyRow = NativeDockApplyRowView()
    private let openNativeDockSettingsItem = NSMenuItem(title: String(localized: "Dock Settings…"), action: #selector(openNativeDockSettings), keyEquivalent: "")
    /// 「钨极 Dock 栏显示在 ▸」：二级子菜单，「跟随鼠标」+ 每块在场屏一项（owner 2026-08-26 把这个
    /// 设置从设置窗口搬到菜单，不两边都放）。做成子菜单是为了**主菜单只多一行、高度恒定**——
    /// 屏幕数变化不会改主菜单高度，任务条那条按左上角定位的路径就不会漂。
    /// 整行的显隐只允许在 `prepareMenuForPresentation` 翻转（菜单开着时增删行的老规矩）。
    private let taskbarScreenItem = NSMenuItem(title: String(localized: "Show taskbar on"), action: nil, keyEquivalent: "")
    /// **刻意不设 delegate**：`menuWillOpen` / `menuDidClose` 不区分 menu 参数，
    /// 子菜单一开一关会被当成主菜单开关，提前解除边缘自动隐藏抑制。内容改为在父菜单
    /// 显示前（`prepareMenuForPresentation`）建好。
    private let taskbarScreenMenu = NSMenu()
    /// 「Dock 栏大小 ▸」：四档静态子菜单，`configureMenu` 建一次，之后只翻勾选。
    /// 做成子菜单而不是四行平铺，同「显示在 ▸」的理由：主菜单只多一行。
    private let dockSizeItem = NSMenuItem(title: String(localized: "Taskbar Size"), action: nil, keyEquivalent: "")
    private let dockSizeMenu = NSMenu()
    /// 下面三条是普通勾选项，**恒在**（菜单开着时不许增删行），勾选状态由 refreshCheckmarks 落。
    private let showShelfItem = NSMenuItem(title: String(localized: "Show Shelf"), action: #selector(toggleShowShelf), keyEquivalent: "")
    private let hoverNameItem = NSMenuItem(title: String(localized: "Show app name on hover"), action: #selector(toggleHoverName), keyEquivalent: "")
    private let windowLiftItem = NSMenuItem(title: String(localized: "Keep maximized windows above the taskbar"), action: #selector(toggleWindowLift), keyEquivalent: "")
    private let nativeDockSliderView: PreferenceSliderMenuItemView
    private let edgeSliderView: PreferenceSliderMenuItemView

    init(store: AppSettingsStore,
         settingsCoordinator: SettingsCoordinator,
         isAccessibilityTrusted: @escaping () -> Bool,
         onShowDebugConsole: @escaping () -> Void,
         onExportDebugSnapshot: @escaping () -> Void,
         onShowSettings: @escaping () -> Void,
         onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in },
         onQuit: @escaping () -> Void,
         hotKeyGlyphs: @escaping () -> String,
         isToggleHotKeyRegistered: @escaping () -> Bool = { false },
         connectedScreens: @escaping () -> [(uuid: String, title: String)] = { [] }) {
        self.store = store
        self.settingsCoordinator = settingsCoordinator
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.onShowDebugConsole = onShowDebugConsole
        self.onExportDebugSnapshot = onExportDebugSnapshot
        self.onShowSettings = onShowSettings
        self.onMenuVisibilityChanged = onMenuVisibilityChanged
        self.onQuit = onQuit
        self.hotKeyGlyphs = hotKeyGlyphs
        self.isToggleHotKeyRegistered = isToggleHotKeyRegistered
        self.connectedScreens = connectedScreens
        nativeDockSliderView = PreferenceSliderMenuItemView(accessibilityTitle: String(localized: "Dock wake delay"))
        edgeSliderView = PreferenceSliderMenuItemView(accessibilityTitle: String(localized: "Tungsten Edge wake delay"))
        super.init()
        configureStatusItem()
        configureMenu()
        refreshCheckmarks()
        refreshInstallUpdateItem(allowsLayoutChange: true)
        // 钨极滑块是即时生效的本地值：⌥⇧⌘D、设置窗口都可能在菜单开着时改它，滑块要跟着动。
        // sink 用 publisher 发出的新值：@Published 在赋值完成前发布，此刻回读 store 是旧值。
        //
        // 系统 Dock 组刻意**没有**同款订阅：草稿在松手写进系统之前系统没变，滑块就不该动。
        // 它的位置由 menuWillOpen 与提交完成后各同步一次。
        edgeDelaySubscription = store.$edgeAutoHideDelay
            .removeDuplicates()
            .sink { [weak self] delay in
                self?.edgeSliderView.sync(delay: delay)
            }
        // 更新提示要在**菜单关着**的时候就出现在图标上——那是它存在的全部意义，
        // 所以不能等 `menuWillOpen`。`objectWillChange` 在赋值完成前发出，
        // 隔一轮再读才拿得到新值（同上面那条注释的理由）。
        pendingUpdateSubscription = settingsCoordinator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshStatusItemBadge()
                // 文字与可用态可以随时跟着变；**行的显隐不行**——菜单开着时增删行，
                // 任务条那条路径按左上角定位，底边会从任务条上沿漂走（行数不变规则）。
                self.refreshInstallUpdateItem(allowsLayoutChange: !self.isMenuOpen)
            }
        refreshStatusItemBadge()
        refreshSystemTruth()
        // 屏幕列表只在拔插时重算一次，菜单打开时读缓存（见 connectedScreensCache）。
        connectedScreensCache = connectedScreens()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.connectedScreensCache = self.connectedScreens()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    private func configureStatusItem() {
        statusItem.button?.image = Self.statusItemImage(badged: false)
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        permissionWarningItem.target = self
        permissionWarningItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: String(localized: "Warning"))
        permissionWarningItem.isHidden = true
        permissionWarningSeparator.isHidden = true
        menu.addItem(permissionWarningItem)
        menu.addItem(permissionWarningSeparator)

        // 登录时启动 = 菜单第一项（owner 2026-08-24 定；权限警告只在异常态出现，不算数）。
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        openLoginItemsSettingsItem.target = self
        menu.addItem(openLoginItemsSettingsItem)
        menu.addItem(.separator())

        // 钨极组排在系统 Dock 组之前——这是钨极自己的菜单，自家的设置在前。
        // 两组都有灰色组标题当"帽子"：从前只有系统 Dock 有，整个菜单只有一顶帽子在上面，
        // 于是它下面的钨极命令看起来也归它管（owner 2026-08-03 反馈）。
        edgeSectionItem.isEnabled = false
        menu.addItem(edgeSectionItem)

        // 钨极滑块即时生效：每拖一格就写进 store。但**光写值看不到效果**——
        // 菜单一打开就设了 `taskbarMenuOpen` 抑制器，任务条被强制保持可见、不许隐藏，
        // 于是拖到 0.5s 也纹丝不动，得关掉菜单才看见（owner 2026-08-03 报的"要取消菜单栏才生效"）。
        //
        // 所以**动了这条滑块就解除抑制**，让任务条按新档位真的动起来：碰滑块 = 要求看效果。
        // 没碰滑块时抑制照旧，菜单开着发呆任务条不会从菜单底下缩掉。
        //
        // **但任务条右键弹出的菜单例外**：它锚在任务条上沿，任务条一缩菜单就悬在半空，
        // 比看不到效果更难受（owner 2026-08-03）。那条路径只写值、不解除抑制，
        // 关掉菜单即生效。`menuDidClose` 之后还会再调一次 false，幂等。
        edgeSliderView.onDelayChange = { [weak self, weak store] delay in
            store?.setEdgeAutoHideDelay(delay)
            guard let self, !self.isPresentedFromTaskbar else { return }
            self.onMenuVisibilityChanged(false)
        }
        let edgeItem = NSMenuItem()
        edgeItem.view = edgeSliderView
        menu.addItem(edgeItem)
        menu.addItem(.separator())

        nativeDockSectionItem.attributedTitle = Self.sectionTitle(AutoHideToggleMenuModel.nativeDockSectionTitle)
        nativeDockSectionItem.isEnabled = false
        menu.addItem(nativeDockSectionItem)

        // 系统 Dock 滑块**不接** store：`setNativeDockAutoHideDelay` 一调用就把 active + remembered
        // 一起落盘，而系统那边要等用户点确认行才写，拖到一半的值不该变成持久状态。
        // onDraftChange 只用来刷新确认行，不碰任何持久状态。
        nativeDockSliderView.onDraftChange = { [weak self] draft in
            self?.refreshNativeDockApplyItem(draft: draft)
        }
        nativeDockSliderView.onDelayCommit = { [weak self] target in
            self?.scheduleNativeDockWrite(target: target)
        }
        let nativeDockSliderItem = NSMenuItem()
        nativeDockSliderItem.view = nativeDockSliderView
        menu.addItem(nativeDockSliderItem)

        nativeDockApplyRow.onApply = { [weak self] in
            self?.applyNativeDockDelay()
        }
        nativeDockApplyItem.view = nativeDockApplyRow
        nativeDockApplyItem.isHidden = true
        menu.addItem(nativeDockApplyItem)

        menu.addItem(.separator())

        // 任务条自身的五项（owner 2026-09-01，当天两次拍板的结果）：**独立成块、不挂组标题**，
        // 排在两条唤醒滑块之后。先并进钨极组试过，owner 看实机后要它离开滑块自成一块。
        // 没有帽子，就靠上下两条分隔线与前后区分——所以这一块**不要再插别的东西**：
        // 一旦混进与任务条无关的行，读者就只能靠文案自己猜它归谁管了。
        // `taskbarScreenItem` 的显隐仍只在 `prepareMenuForPresentation` 翻转
        //（菜单在屏时增删行会让任务条弹出路径的锚点漂移）。
        taskbarScreenItem.submenu = taskbarScreenMenu
        taskbarScreenItem.isHidden = true
        menu.addItem(taskbarScreenItem)

        // 大小子菜单是静态的四档，建一次即可；勾选交给 refreshCheckmarks。
        for size in DockSize.allCases {
            let sizeItem = NSMenuItem(title: size.title, action: #selector(selectDockSize(_:)), keyEquivalent: "")
            sizeItem.target = self
            // rawValue 走 representedObject。**不能用 `ClosureMenuItem`**：
            // `AppMenuFragments.swift` 只编进 app target，本文件在测试 target 也编译。
            sizeItem.representedObject = size.rawValue
            dockSizeMenu.addItem(sizeItem)
        }
        dockSizeItem.submenu = dockSizeMenu
        menu.addItem(dockSizeItem)

        // 三个开关。设置窗口里它们各带一行灰色说明，菜单里没有副标题的位置，
        // 说明随搬家一并删除（owner 2026-09-01 拍板接受这个代价）。
        showShelfItem.target = self
        menu.addItem(showShelfItem)
        hoverNameItem.target = self
        menu.addItem(hoverNameItem)
        windowLiftItem.target = self
        menu.addItem(windowLiftItem)
        menu.addItem(.separator())
        #if DEBUG
        let debugMenu = NSMenu()
        let showDebug = NSMenuItem(title: String(localized: "Show Debug Console"), action: #selector(showDebugConsole), keyEquivalent: "")
        showDebug.target = self
        debugMenu.addItem(showDebug)
        let exportSnapshot = NSMenuItem(title: String(localized: "Export Taskbar Snapshot"), action: #selector(exportDebugSnapshot), keyEquivalent: "")
        exportSnapshot.target = self
        debugMenu.addItem(exportSnapshot)
        let debugItem = NSMenuItem(title: String(localized: "Debug"), action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        menu.addItem(.separator())
        #endif

        // 「设置…」和「退出」归为底部一组（owner 2026-08-03）：菜单栏应用的普遍习惯是
        // 把这类"进另一个界面"的入口放在下面，上面留给随手切的开关。
        // 登录项 / 检查更新 / 版本号已于 2026-08-24 去重，只留设置窗口。
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        // 和「设置…」并列：两条都是"打开另一个界面"。它因此离开了系统 Dock 组
        //（owner 2026-08-03；原先它是那组的末行，和下一组的首行看起来像一对）。
        openNativeDockSettingsItem.target = self
        menu.addItem(openNativeDockSettingsItem)

        installUpdateItem.target = self
        installUpdateItem.isHidden = true
        menu.addItem(installUpdateItem)

        let quitItem = NSMenuItem(title: String(localized: "Quit Tungsten Edge"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }


    /// 任务条 / 胶囊右键的弹出入口。
    ///
    /// 和状态栏图标**共用同一个 `NSMenu` 实例**：菜单里的两条滑块和确认按钮是有状态的自绘 NSView，
    /// 克隆一份会立刻出现"两个滑块各记各的草稿"。`menuWillOpen` 的既有逻辑（回灌系统 Dock 真值、
    /// 刷新勾选、丢弃未确认草稿）走的是同一个 delegate，所以两个入口行为完全一致。
    func popUpFromTaskbar(with event: NSEvent, in view: NSView) {
        // 自己算锚点，让菜单**底边贴任务条上沿**、左边对齐鼠标——像右键系统程序坞那样浮在条的
        // 上方，不遮挡它。交给 `NSMenu.popUpContextMenu` 自动翻转的话，实测菜单底边会落在鼠标
        // 下方 28pt，把整条任务条盖住（owner 2026-08-03 反馈"不跟手"的一半原因）。
        //
        // `MenuHostNSView` 是普通 NSView（`isFlipped == false`，原点在左下），它铺满任务条
        // 可视区，所以 `bounds.maxY` 就是任务条上沿；`popUp(positioning:at:in:)` 把菜单
        // **左上角**放在给定点，于是再往上抬一个菜单高度。
        isPresentedFromTaskbar = true
        prepareMenuForPresentation()
        isPreparedForTaskbarPresentation = true
        let local = view.convert(event.locationInWindow, from: nil)
        let anchor = NSPoint(x: local.x, y: view.bounds.maxY + menu.size.height)
        menu.popUp(positioning: nil, at: anchor, in: view)
        isPreparedForTaskbarPresentation = false
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        isPresentedFromTaskbar = false
        onMenuVisibilityChanged(false)
        // 关闭后再预热一次；所有结果只进缓存，供下次展示直接使用。
        refreshSystemTruth()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        onMenuVisibilityChanged(true)
        if !isPreparedForTaskbarPresentation {
            prepareMenuForPresentation()
        }
        isPreparedForTaskbarPresentation = false
        refreshSystemTruth()
    }

    /// 只读本地缓存并同步 AppKit 对象，不执行任何系统 I/O。
    /// 任务条入口会在量 `menu.size` 前先走这里，确保锚点使用本次真实高度。
    private func prepareMenuForPresentation() {
        let granted = isAccessibilityTrusted()
        permissionWarningItem.isHidden = granted
        permissionWarningSeparator.isHidden = granted
        refreshCheckmarks()
        refreshInstallUpdateItem(allowsLayoutChange: true)
        // 没点确认就关菜单 = 作废：什么都不写，下次打开一切从系统真值重新起步。
        // （否则「随手拨一下看看」也会招来一次 killall Dock——关个菜单屏幕突然闪一下，
        // 正是这次要消除的怪异感。）
        //
        // **作废放在「打开时」而不是 `menuDidClose`**，是为了不依赖确认控件的形态。
        // 现在的确认是自定义 view 里的 `NSButton`，action 直接发送，放哪儿都安全；
        // 但只要有人把它改回普通 `NSMenuItem`，`menuDidClose` 就会变成陷阱——AppKit 的顺序是
        // 先关菜单、`menuDidClose` 回调、**然后**才发送菜单项 action，草稿会赶在确认之前
        // 被清空，`commitDraft()` 拿到 nil，整个确认功能静默失效（本轮踩过并修掉）。
        nativeDockSliderView.discardDraft()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        nativeDockApplyItem.isHidden = true
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
        refreshEdgeSectionTitle()
        rebuildTaskbarScreenMenu()
    }

    /// 重建「钨极 Dock 栏显示在 ▸」。**只从 `prepareMenuForPresentation` 调**——它是唯一
    /// 允许改行显隐的路径（菜单在屏时增删行会让任务条锚点漂移）。
    private func rebuildTaskbarScreenMenu() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: store.taskbarScreenPlacement,
            connectedScreens: connectedScreensCache
        )
        taskbarScreenItem.isHidden = presentation.isHidden
        taskbarScreenMenu.removeAllItems()
        for item in presentation.items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(selectTaskbarScreen(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            // 选择以 token 字符串走 representedObject。**不能用 ClosureMenuItem**：
            // `AppMenuFragments.swift` 只编进 app target，本文件在测试 target 也编译。
            menuItem.representedObject = item.selection.token
            menuItem.state = item.isChecked ? .on : .off
            taskbarScreenMenu.addItem(menuItem)
        }
    }

    /// 系统读取在服务专用队列执行。任务条菜单按左上角定位，显示后改高度会让底边漂移，
    /// 所以那条路径只更新缓存；状态栏菜单没有这个锚点约束，可以就地吸收新真值。
    /// （登录项那半 2026-08-24 随去重删过一轮，owner 复议登录项回菜单后一并恢复。）
    private func refreshSystemTruth() {
        systemTruthRefreshTask?.cancel()
        let settingsCoordinator = settingsCoordinator
        systemTruthRefreshTask = Task { @MainActor [weak self] in
            async let launchAccepted = settingsCoordinator.refreshLaunchAtLoginState()
            async let nativeDockAccepted = settingsCoordinator.reconcileNativeDockMirror()
            let accepted = await (launchAccepted, nativeDockAccepted)
            guard let self,
                  !Task.isCancelled,
                  self.isMenuOpen,
                  !self.isPresentedFromTaskbar else { return }
            if accepted.0 {
                self.refreshCheckmarks(allowsLayoutChange: false)
            }
            // 滑块只在用户还没开始拖的时候才跟着真值走——正在拖的手不能被跳一下。
            if accepted.1, !self.nativeDockSliderView.hasDraft {
                self.nativeDockSliderView.sync(delay: self.store.nativeDockAutoHideDelay)
            }
        }
    }

    /// 组标题**不设 `keyEquivalent`**：禁用行设了会被菜单捕获，还会让它看起来能点。
    /// ⌥⇧⌘D 只以纯文字写进标题，且只在 Carbon 注册成功时才提——注册失败时按不出来，写上去是骗人。
    private func refreshEdgeSectionTitle() {
        edgeSectionItem.attributedTitle = Self.sectionTitle(
            AutoHideToggleMenuModel.edgeSectionTitle(
                isHotKeyRegistered: isToggleHotKeyRegistered(),
                glyphs: hotKeyGlyphs()
            )
        )
    }

    /// 草稿与已生效值不同才浮出确认行。已生效值取本地镜像——`menuWillOpen` 刚把它对齐过系统真值。
    private func refreshNativeDockApplyItem(draft: Double) {
        let shouldShow = AutoHideToggleMenuModel.shouldShowNativeApply(
            draft: draft,
            applied: store.nativeDockAutoHideDelay
        )
        nativeDockApplyItem.isHidden = !shouldShow
        if shouldShow {
            // 按钮标题恒为「应用」，目标档位只进 accessibility——滑块上已经用数值和端点圆点
            // 表达过一次，按钮里再重复反而挤；但 VoiceOver 只听得到这一句，必须带上档位。
            nativeDockApplyRow.updateTarget(description: AutoHideToggleMenuModel.nativeApplyTitle(draft: draft))
            // 上一轮可能停在 hover 态，而这一轮浮出时鼠标还在滑块上，不在按钮上。
            nativeDockApplyRow.resetInteractionState()
        }
    }

    private func applyNativeDockDelay() {
        nativeDockSliderView.commitDraft()
    }

    @objc private func openNativeDockSettings() {
        guard settingsCoordinator.openNativeDockSettings() else {
            presentError(
                title: String(localized: "Can’t Open Dock Settings"),
                message: String(localized: "Open System Settings and go to Desktop & Dock (on macOS 12, Dock & Menu Bar).")
            )
            return
        }
    }

    /// `allowsLayoutChange` = 本次刷新可不可以增删菜单行。展示前（`prepareMenuForPresentation`）
    /// 可以，异步真值回来时**不可以**——理由见 `refreshLaunchAtLoginState`。
    private func refreshCheckmarks(allowsLayoutChange: Bool = true) {
        refreshLaunchAtLoginState(allowsLayoutChange: allowsLayoutChange)
        refreshTaskbarPreferenceStates()
    }

    /// 钨极组四项的勾选。**只改 `state`，不增删行也不翻 `isHidden`**，
    /// 所以菜单开着时调用也安全（不受 `allowsLayoutChange` 约束）。
    private func refreshTaskbarPreferenceStates() {
        showShelfItem.state = store.showShelf ? .on : .off
        hoverNameItem.state = store.hoverStyle.isExpressive ? .on : .off
        windowLiftItem.state = store.windowLiftEnabled ? .on : .off
        let current = store.dockSize.rawValue
        for item in dockSizeMenu.items {
            item.state = (item.representedObject as? String) == current ? .on : .off
        }
    }

    private func refreshLaunchAtLoginState(allowsLayoutChange: Bool) {
        let presentation = LaunchAtLoginMenuPresentation(state: settingsCoordinator.launchAtLoginState)
        launchAtLoginItem.title = presentation.title
        launchAtLoginItem.state = presentation.isChecked ? .on : .off
        launchAtLoginItem.isEnabled = presentation.isEnabled
        // 菜单已经在屏幕上时**只改文字与勾选，绝不增删行**。登录项处于 `.requiresApproval`
        //（刚注册、等系统设置里批准）时这一行会冒出来，异步真值回来得晚，行一多菜单高度就变——
        // 用户看到的是"内容自己跳了一下"，而任务条那条路径按左上角定位，高度一变底边还会漂。
        // 迟一轮不要紧：下次 `prepareMenuForPresentation` 在菜单显示**之前**会补上。
        guard allowsLayoutChange else { return }
        openLoginItemsSettingsItem.isHidden = !presentation.showsSettingsItem
    }

    /// 「安装 vX.Y.Z…」行的唯一刷新入口。`allowsLayoutChange` = 本次刷新可不可以改行的显隐：
    /// 展示前（`prepareMenuForPresentation`）与菜单关着时可以，菜单开着时**不可以**——
    /// 增删行会改菜单高度，任务条那条路径按左上角定位，底边会从任务条上沿漂走。
    /// 迟一轮不要紧：下次 `prepareMenuForPresentation` 在菜单显示**之前**会补上。
    private func refreshInstallUpdateItem(allowsLayoutChange: Bool) {
        // 有一版在等着装的时候，这行直接写出版本号并挂一个红点（owner 2026-08-20 画的样子）——
        // 「安装 0.9.2…」加个红点是一条消息；主动的「检查更新…」入口只在设置窗口（2026-08-24）。
        if let version = settingsCoordinator.pendingUpdateVersion {
            let title = String(format: String(localized: "Install %@…"), version)
            installUpdateItem.title = title
            installUpdateItem.attributedTitle = Self.pendingUpdateTitle(title)
            // 那个「●」在 VoiceOver 里会被念成「实心圆」，所以另给一句人话。
            installUpdateItem.setAccessibilityLabel(
                String(format: String(localized: "Install %@ — update available"), version)
            )
            // 可用态归 Sparkle：正在下载 / 安装时它自己会报 false，不再维护"在飞"标志。
            installUpdateItem.isEnabled = settingsCoordinator.canCheckForUpdates
            if allowsLayoutChange { installUpdateItem.isHidden = false }
        } else {
            // ⚠️ attributedTitle 必须清回 nil。留着的话 `title` 再怎么改都不生效，
            // 这行会永远卡在上一次那个版本号上。
            installUpdateItem.attributedTitle = nil
            installUpdateItem.setAccessibilityLabel(nil)
            if allowsLayoutChange { installUpdateItem.isHidden = true }
        }
    }

    /// 两条分组标题的样式。**必须走 `attributedTitle`**：组标题是 `action: nil` 的 disabled 项，
    /// 没有 `textColor` 可设，系统按 disabled 画成菜单里最淡的一档，owner 2026-09-01 嫌太灰。
    /// 加深到 `secondaryLabelColor`——比可点的菜单项弱，但看得清；**不要为了变黑把它改成
    /// enabled**，那样鼠标划过会高亮成蓝条，而组标题不高亮是对的（owner 2026-08-04）。
    ///
    /// ⚠️ 字体必须显式给：`attributedTitle` 不给就掉成系统默认字号（同 `pendingUpdateTitle`）。
    /// ⚠️ 设了 `attributedTitle` 之后**再赋 `title` 不生效**——所以 `refreshEdgeSectionTitle()`
    /// 也得走这里，两处调用点不能只改一处。
    private static func sectionTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    /// 「安装 X.Y.Z…」+ 右上角一个红点。
    ///
    /// ⚠️ **标题部分必须显式给颜色和字体**：`attributedTitle` 不给就是死黑 + 系统默认字号，
    /// 深色菜单下直接看不见。红点这里可以是真红色——菜单背景不是菜单栏，
    /// 没有菜单栏图标那条 template 反色的约束（那一条见 `statusItemImage(badged:)`）。
    private static func pendingUpdateTitle(_ title: String) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        text.append(NSAttributedString(
            string: "●",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.systemRed,
                // 抬到文字右上角，贴着最后一个字符——owner 画的就是这个位置。
                .baselineOffset: 5
            ]
        ))
        return text
    }

    /// 菜单栏图标：有待装的新版时点一个小圆点。
    ///
    /// **必须和菜单项分开刷**——菜单项只在菜单将开时同步，而这个点的全部意义就是
    /// 「菜单没打开时也看得见」。所以它挂在 `settingsCoordinator` 的变更订阅上。
    private func refreshStatusItemBadge() {
        statusItem.button?.image = Self.statusItemImage(
            badged: settingsCoordinator.pendingUpdateVersion != nil
        )
    }

    /// 状态栏图标。`badged` 时在右上角画一个小圆点。
    ///
    /// ⚠️ **整张图仍然是 template**（单色，由系统按明暗和高亮自动反色）。圆点做不成红色：
    /// 红点要求 `isTemplate = false`，那会一并丢掉系统的自动反色，深色菜单栏和菜单展开时
    /// 的高亮底上图标都会糊掉。所以用「先挖空一圈、再填实心点」的画法让它和图形本体分开，
    /// 靠形状而不是颜色让人看见。
    private static func statusItemImage(badged: Bool) -> NSImage? {
        let base = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.3.offgrid.fill", accessibilityDescription: "Tungsten Edge")
        guard let base else { return nil }
        base.isTemplate = true
        guard badged else {
            base.accessibilityDescription = "Tungsten Edge"
            return base
        }

        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)

            let diameter = max(3.5, size.width * 0.24)
            let dot = NSRect(
                x: rect.maxX - diameter,
                y: rect.maxY - diameter,
                width: diameter,
                height: diameter
            )
            // 先把点周围掏空一圈，再填实心——否则单色的点贴在同样单色的图形上会连成一片。
            let moat = dot.insetBy(dx: -1.2, dy: -1.2)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: moat).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Tungsten Edge — update available")
        return image
    }

    @objc private func toggleLaunchAtLogin() {
        guard let enable = LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: settingsCoordinator.launchAtLoginState) else { return }
        if case .failure(let error) = settingsCoordinator.setLaunchAtLogin(enable) {
            presentError(title: String(localized: "Couldn’t Change Open at Login"), message: error.localizedDescription)
        }
        refreshCheckmarks()
    }

    @objc private func selectTaskbarScreen(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String,
              let selection = TaskbarScreenMenuPresentation.Selection(token: token) else { return }
        switch selection {
        case .followMouse:
            store.setTaskbarScreenPlacement(.followMouse)
        case .allScreens:
            store.setTaskbarScreenPlacement(.allScreens)
        case .allScreensPerDisplay:
            store.setTaskbarScreenPlacement(.allScreensPerDisplay)
        case .screen(let uuid):
            // name 只是展示快照：在场屏取去重后的展示名；重选那块断开的屏时沿用旧快照。
            let name = connectedScreensCache.first(where: { $0.uuid == uuid })?.title
                ?? store.taskbarScreenPlacement.pinnedSelection?.name
                ?? ""
            store.setTaskbarScreenPlacement(.pinned(PinnedScreenSelection(uuid: uuid, name: name)))
        }
    }

    @objc private func selectDockSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = DockSize(rawValue: raw) else { return }
        store.setDockSize(size)
        refreshCheckmarks()
    }

    @objc private func toggleShowShelf() {
        store.setShowShelf(!store.showShelf)
        refreshCheckmarks()
    }

    /// 悬停显示应用名 = `hoverStyle` 的两档（`.standard` 显示 / `.quiet` 不显示），
    /// 不是独立的布尔字段——设置窗口那版也是这么读写的，别在这里另开一个镜像。
    @objc private func toggleHoverName() {
        store.setHoverStyle(store.hoverStyle.isExpressive ? .quiet : .standard)
        refreshCheckmarks()
    }

    @objc private func toggleWindowLift() {
        store.setWindowLiftEnabled(!store.windowLiftEnabled)
        refreshCheckmarks()
    }

    @objc private func openLoginItemsSettings() {
        settingsCoordinator.openLoginItemsSettings()
    }

    /// Sparkle 自带全套结果界面，而且用户主动发起的检查它保证会置前，
    /// 所以这里既不用 `NSAlert`、也不用 `runModalInForeground`。
    /// 只从「安装 vX.Y.Z…」触发：对一版已就绪的更新，`checkForUpdates()` 就是「继续安装」；
    /// 主动检查的入口在设置窗口（2026-08-24 菜单去重）。
    @objc private func installPendingUpdate() {
        menu.cancelTrackingWithoutAnimation()
        settingsCoordinator.checkForUpdates()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = AccessibilitySettingsLink.url else { return }
        NSWorkspace.shared.open(url)
    }


    /// 系统 Dock 的唯一写入路径。先收菜单——写入以 `killall Dock` 收尾，
    /// 菜单不该在系统 Dock 重启时还开着；下一轮再执行。
    private func scheduleNativeDockWrite(target: Double) {
        menu.cancelTrackingWithoutAnimation()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.settingsCoordinator.applyNativeDock(target: target)
            self.nativeDockSliderView.sync(delay: outcome.resolvedDelay)
            self.nativeDockApplyItem.isHidden = true
            if let error = outcome.error {
                self.presentError(title: String(localized: "Couldn’t Change Dock Settings"), message: error.localizedDescription)
            }
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        Self.runModalInForeground(alert)
    }

    /// 钨极是 `.accessory` 应用（无程序坞图标）。这类应用直接 `runModal()` 时**不会**把自己
    /// 带到前台，弹窗会落在当前前台应用的窗口后面——用户点了菜单项却看不到任何反应，
    /// 表现和「功能坏了」完全一样（真实用户就是这么报的「检查更新失效」）。
    /// 只要前台有任何窗口就中招，也就是几乎总是中招。
    ///
    /// `AppDelegate` 里每个 `runModal()` / 面板展示之前都调了 `NSApp.activate`，
    /// 唯独状态菜单这四处漏了。所有弹窗一律走这里，别再各自 `runModal()`。
    @discardableResult
    private static func runModalInForeground(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    @objc private func showDebugConsole() { onShowDebugConsole() }
    @objc private func exportDebugSnapshot() { onExportDebugSnapshot() }
    @objc private func showSettings() {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [onShowSettings] in onShowSettings() }
    }
    @objc private func quit() { onQuit() }
}

@MainActor
final class PreferenceSliderMenuItemView: NSView {
    /// 每一格变化。即时生效型滑块（钨极，本地值）在这里直接写 store。
    var onDelayChange: ((Double) -> Void)?
    /// 草稿落定（鼠标松手，或键盘每调一格）。确认型滑块用它刷新确认行，
    /// **绝不能拿来写任何持久状态**——草稿的全部意义就是「还没生效」。
    var onDraftChange: ((Double) -> Void)?
    /// 确认提交。**设了它就启用草稿机制**：系统 Dock 每次写入都以 `killall Dock` 收尾、
    /// 屏幕必然闪一下，那一下只能发生在用户主动确认之后。
    var onDelayCommit: ((_ target: Double) -> Void)?

    /// 选中那一端的小字颜色：强调色**带一点透明**（owner 2026-08-03）。
    /// 实心圆点保持满强度，小字比它弱一档——圆点是主标记，小字是它的回声。
    /// 别把这个透明度做到字重上：加粗会让标签宽度变化、两端文字左右跳动。
    static let activeEndpointColor = NSColor.controlAccentColor.withAlphaComponent(0.7)

    /// 未选中那一端的小字颜色。**四个使用点必须都引用它**（左右各一次初始化 + `updateDisplay`
    /// 里左右各一次），散成四份字面量时漏改一份只有「拖到端点再拖回来」才看得见。
    /// 2026-09-01 由三级标签色深一档到这里（owner 嫌整块太灰）。
    /// 端点**圆点**的空心描边不跟着动——那是图形不是文字。
    static let inactiveEndpointColor = NSColor.secondaryLabelColor

    /// 用户已经动过滑块、还没提交。菜单显示后补读系统真值时要看它——正在拖的手不能被跳一下。
    var hasDraft: Bool { commitTracker.hasPending }

    private let accessibilityTitle: String
    private var delay = 0.0
    private var commitTracker = PreferenceSliderCommitTracker()
    private var displayString = "0.0s"
    private let leftEndpointDot = EndpointDotView()
    private let rightEndpointDot = EndpointDotView()
    private let delayLabel = NSTextField(labelWithString: "")
    // 端点小标签只有 34pt 宽（见 layout() 的 sliderSideInset），是刻度标记不是档位名：
    // 完整档位名由中间那行大字（delayLabel ← delayDisplayName）显示，那里有 ~190pt。
    // 英文因此用短词——实测 "Always Visible" 在 9pt 字体下 62.5pt，放不进 34pt。
    private let leftEndpointLabel = NSTextField(labelWithString: String(localized: "Always"))
    private let rightEndpointLabel = NSTextField(labelWithString: String(localized: "Never"))
    private let slider = MenuTrackingSlider()

    init(accessibilityTitle: String) {
        self.accessibilityTitle = accessibilityTitle
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        autoresizingMask = [.width]
        configureSubviews()
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityValue() -> Any? {
        displayString
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let width = window?.frame.width, width > frame.width {
            frame.size.width = width
        }
    }

    func sync(delay: Double) {
        let index = AppSettingsStore.sliderIndexFromDelay(delay)
        self.delay = AppSettingsStore.delayFromSliderIndex(index)
        slider.integerValue = index
        updateDisplay()
    }

    private func configureSubviews() {
        wantsLayer = true

        leftEndpointDot.setAccessibilityElement(false)
        addSubview(leftEndpointDot)

        rightEndpointDot.setAccessibilityElement(false)
        addSubview(rightEndpointDot)

        delayLabel.font = .systemFont(ofSize: 11)
        delayLabel.textColor = .secondaryLabelColor
        delayLabel.alignment = .center
        addSubview(delayLabel)

        leftEndpointLabel.font = .systemFont(ofSize: 9)
        leftEndpointLabel.textColor = Self.inactiveEndpointColor
        leftEndpointLabel.alignment = .center
        leftEndpointLabel.setAccessibilityElement(false)
        addSubview(leftEndpointLabel)

        rightEndpointLabel.font = .systemFont(ofSize: 9)
        rightEndpointLabel.textColor = Self.inactiveEndpointColor
        rightEndpointLabel.alignment = .center
        rightEndpointLabel.setAccessibilityElement(false)
        addSubview(rightEndpointLabel)

        slider.minValue = 0
        slider.maxValue = Double(AppSettingsStore.sliderIndexMax)
        slider.integerValue = AppSettingsStore.sliderIndexFromDelay(delay)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.onTrackingStarted = { [weak self] in
            guard let self else { return }
            self.commitTracker.begin(currentDelay: self.delay)
        }
        slider.onTrackingEnded = { [weak self] in
            // 拖动全程不碰确认行：每经过一格就增删一次菜单项会让整个菜单反复重排。
            // 松手才刷新这一次。
            guard let self else { return }
            self.onDraftChange?(self.delay)
        }
        addSubview(slider)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let contentX = StatusMenuLayout.textInsetX
        let contentWidth = bounds.width - contentX - StatusMenuLayout.trailingInsetX
        let labelY: CGFloat = 28
        let sliderY: CGFloat = 10

        let sliderSideInset: CGFloat = 34
        let sliderX = contentX + sliderSideInset
        let sliderWidth = max(0, contentWidth - sliderSideInset * 2)
        delayLabel.frame = NSRect(x: sliderX, y: labelY, width: sliderWidth, height: 14)

        let dotY = sliderY + 6
        leftEndpointDot.frame = NSRect(x: contentX + 14, y: dotY, width: dotSize, height: dotSize)
        slider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: 20)
        rightEndpointDot.frame = NSRect(x: slider.frame.maxX + 12, y: dotY, width: dotSize, height: dotSize)
        leftEndpointLabel.frame = NSRect(x: contentX, y: labelY, width: sliderSideInset, height: 14)
        rightEndpointLabel.frame = NSRect(x: slider.frame.maxX, y: labelY, width: sliderSideInset, height: 14)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = min(max(Int(sender.doubleValue.rounded()), 0), AppSettingsStore.sliderIndexMax)
        sender.integerValue = index
        let previousDelay = delay
        delay = AppSettingsStore.delayFromSliderIndex(index)
        updateDisplay()
        onDelayChange?(delay)

        guard onDelayCommit != nil else { return }
        // 键盘 / VoiceOver 调整不经过 mouseDown，没有 tracking 起点，这里补一个
        // （鼠标路径里 begin 已由 onTrackingStarted 调过，重复调用不覆盖起点）。
        commitTracker.begin(currentDelay: previousDelay)
        commitTracker.stage(delay)
        // 键盘 / VoiceOver 没有「松手」这个时刻，只能当场刷新确认行。它们因此和鼠标
        // 走同一条确认路径，不再需要 debounce 自动提交，也就不会再被静默丢弃。
        if !slider.isMouseTracking {
            onDraftChange?(delay)
        }
    }

    /// 用户按下确认行。**唯一**的提交入口——滑块自己在任何情况下都不写系统。
    func commitDraft() {
        guard let commit = commitTracker.consume() else { return }
        onDelayCommit?(commit.target)
    }

    /// 未确认的草稿作废，滑块拨回草稿开始前的已生效值。
    /// 调用点是**菜单打开时**（`menuWillOpen`），不是关闭时——理由见那里。
    /// 已被 `commitDraft` 消费过就拿到 nil，不会把刚确认的新值又拨回去。
    func discardDraft() {
        guard let discarded = commitTracker.consume() else { return }
        sync(delay: discarded.previous)
    }

    private func updateDisplay() {
        let index = slider.integerValue
        displayString = displayString(for: index)
        delay = AppSettingsStore.delayFromSliderIndex(index)
        delayLabel.stringValue = displayString
        // 两端「常驻/不唤醒」小字恒定可见；选中时圆点变实心、**小字同时染成强调色**
        //（owner 2026-08-03：光靠圆点不够明显）。**只换颜色、不加粗**——加粗会让这一行的
        // 排版宽度变化、两端标签左右跳动。
        // 中间数值文字到达端点时改为隐藏，避免和恒定可见的端点小字重复显示同一个词。
        let isAtLeftEnd = index == 0
        let isAtRightEnd = index == AppSettingsStore.sliderIndexMax
        delayLabel.isHidden = isAtLeftEnd || isAtRightEnd
        leftEndpointDot.isOn = isAtLeftEnd
        rightEndpointDot.isOn = isAtRightEnd
        leftEndpointLabel.textColor = isAtLeftEnd ? Self.activeEndpointColor : Self.inactiveEndpointColor
        rightEndpointLabel.textColor = isAtRightEnd ? Self.activeEndpointColor : Self.inactiveEndpointColor
        setAccessibilityLabel("\(accessibilityTitle)，\(displayString)")
        setAccessibilityValue(displayString)
        slider.displayString = displayString
    }

    /// 与确认行共用一份档位口径，免得确认行说的和滑块上显示的不是一回事。
    private func displayString(for index: Int) -> String {
        AutoHideToggleMenuModel.delayDisplayName(sliderIndex: index)
    }
}

/// 系统 Dock 滑块的确认按钮行。做成**按钮**而不是普通菜单文字行是有意的：
/// 菜单行和它的邻居视觉权重相同，用户刚拖完滑块、视线还在滑块上，很容易整行错过；
/// 一旦错过就直接关菜单，结果是「以为设好了其实没生效」——比原本那一下闪更糟。
/// 按钮的形态本身就在说「这是要点的东西」。
///
/// 左侧那句小灰字不是装饰：`killall Dock` 的闪消除不了，提前说明白它才不显得怪。
@MainActor
final class NativeDockApplyRowView: NSView {
    var onApply: (() -> Void)?

    private let hintLabel = NSTextField(labelWithString: String(localized: "The Dock will restart"))
    private let applyButton = MenuActionButton(title: String(localized: "Apply"))

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 42))
        autoresizingMask = [.width]
        configureSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 按钮标题恒为「应用」，目标档位只走 accessibility：滑块上已经显示过档位，
    /// 但 VoiceOver 用户听不到滑块，这句是他们唯一的信息来源。
    func updateTarget(description: String) {
        applyButton.setAccessibilityLabel(description)
        setAccessibilityLabel(description)
    }

    /// 每次浮出都从静息态开始：上一轮可能停在 hover 态，而菜单重开时鼠标未必还在按钮上。
    func resetInteractionState() {
        applyButton.resetInteractionState()
    }

    private func configureSubviews() {
        wantsLayer = true

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.setAccessibilityElement(false)
        addSubview(hintLabel)

        applyButton.onClick = { [weak self] in
            self?.onApply?()
        }
        addSubview(applyButton)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let contentX = StatusMenuLayout.textInsetX
        let rightEdge = bounds.width - StatusMenuLayout.trailingInsetX

        let buttonSize = applyButton.intrinsicContentSize
        applyButton.frame = NSRect(
            x: rightEdge - buttonSize.width,
            y: (bounds.height - buttonSize.height) / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )

        let hintWidth = max(0, applyButton.frame.minX - 8 - contentX)
        hintLabel.frame = NSRect(x: contentX, y: (bounds.height - 14) / 2, width: hintWidth, height: 14)
    }

}

/// 菜单里的强调按钮，**自绘**。
///
/// 用 `NSButton` 试过：一旦设了 `bezelColor` 把底色改成强调色，AppKit 自己那套按下变暗
/// 基本被盖住；而菜单打开时 run loop 处在事件追踪模式，标准按钮的 hover / 按下态在这里
/// 都不可靠——按上去像块死图（owner 2026-08-02 报「按钮怎么没有反馈交互」）。
/// 自绘之后三态完全可控：静息 / 悬停（提亮）/ 按下（压暗）。
final class MenuActionButton: NSView {
    var onClick: (() -> Void)?

    private let title: String
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private var isHovering = false { didSet { if isHovering != oldValue { needsDisplay = true } } }
    private var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }

    private static let cornerRadius: CGFloat = 6
    private static let horizontalPadding: CGFloat = 12
    private static let iconTitleGap: CGFloat = 5
    private static let height: CGFloat = 25

    /// 通透而不是实心（owner 2026-08-02 定）：菜单本身是半透明材质，压一块强调色实心
    /// 在上面显得又厚又重。改成淡强调色底 + 强调色字，颜色还在、分量降下来。
    private static let restingAlpha: CGFloat = 0.16
    private static let hoverAlpha: CGFloat = 0.30
    private static let pressedAlpha: CGFloat = 0.42

    init(title: String) {
        self.title = title
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: 92, height: Self.height))
        wantsLayer = true

        // 字重用常规（owner 2026-08-02 定）；文字取强调色本身而不是白色——
        // 白字要靠实心底才立得住，通透底上只有强调色字才够清楚。
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        iconView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        iconView.contentTintColor = .controlAccentColor
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let titleWidth = titleLabel.intrinsicContentSize.width
        let iconWidth = iconView.image?.size.width ?? 0
        return NSSize(
            width: Self.horizontalPadding * 2 + iconWidth + Self.iconTitleGap + titleWidth,
            height: Self.height
        )
    }

    /// 菜单里的自定义 view 不属于 key window，不重写这个第一次点击会被整个吞掉——
    /// 用户会以为按钮坏了。`MenuTrackingSlider` 同理。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 子视图（文字、图标）不能把鼠标事件截走，否则按钮中间一块点不动。
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    func resetInteractionState() {
        isHovering = false
        isPressed = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways`：菜单面板不是 key window，`.activeInKeyWindow` 在这里永远不触发。
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// 菜单事件追踪期间 `mouseUp` 不会自然回到这里，必须自己跑一轮 tracking——
    /// 这和 `MenuTrackingSlider` 靠 `super.mouseDown` 阻塞到松手是同一个道理。
    /// 期间跟踪指针在不在按钮内：拖出去再松手 = 取消，和系统按钮的行为一致。
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        var releasedInside = true

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { trackedEvent, stop in
            guard let trackedEvent else {
                stop.pointee = true
                return
            }
            let local = self.convert(trackedEvent.locationInWindow, from: nil)
            releasedInside = self.bounds.contains(local)
            self.isPressed = releasedInside
            if trackedEvent.type == .leftMouseUp {
                stop.pointee = true
            }
        }

        isPressed = false
        isHovering = releasedInside
        if releasedInside {
            onClick?()
        }
    }

    /// 单测入口：真实路径是上面那轮 tracking loop，测试环境跑不了事件循环。
    func performClickForTesting() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 三态只改透明度，不改色相：底始终是同一个强调色，按下去只是"更实"一点。
        let alpha: CGFloat
        if isPressed {
            alpha = Self.pressedAlpha
        } else if isHovering {
            alpha = Self.hoverAlpha
        } else {
            alpha = Self.restingAlpha
        }
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
        shape.fill()
    }

    override func layout() {
        super.layout()
        let iconSize = iconView.image?.size ?? .zero
        let titleSize = titleLabel.intrinsicContentSize
        let contentWidth = iconSize.width + Self.iconTitleGap + titleSize.width
        let startX = (bounds.width - contentWidth) / 2

        iconView.frame = NSRect(
            x: startX,
            y: (bounds.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        titleLabel.frame = NSRect(
            x: iconView.frame.maxX + Self.iconTitleGap,
            y: (bounds.height - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )
    }
}

final class EndpointDotView: NSView {
    var isOn = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(ovalIn: rect)
        (isOn ? NSColor.controlAccentColor : .clear).setFill()
        path.fill()
        (isOn ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

final class MenuTrackingSlider: NSSlider {
    var displayString = "0.0s"
    var onTrackingStarted: (() -> Void)?
    var onTrackingEnded: (() -> Void)?
    /// `mouseDown` 在拖动全程不返回，因此这个标志就是「当前是不是鼠标拖动」的准确答案，
    /// 用来把键盘 / 辅助功能路径分流到 debounce 提交。
    private(set) var isMouseTracking = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isMouseTracking = true
        onTrackingStarted?()
        super.mouseDown(with: event)
        isMouseTracking = false
        onTrackingEnded?()
    }

    override func accessibilityValue() -> Any? {
        displayString
    }
}

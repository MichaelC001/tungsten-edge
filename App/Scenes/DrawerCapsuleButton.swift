import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drawer Capsule Button

struct DrawerCapsuleButton: View {
    @Environment(\.isPanelHeightResizing) private var isPanelHeightResizing
    @EnvironmentObject var runtime: AppRuntime
    @EnvironmentObject var drawerStore: DrawerStore
    @EnvironmentObject var keptAppStore: KeptAppStore
    @EnvironmentObject var messagingStore: MessagingAppStore
    @EnvironmentObject var runningApplicationStore: RunningApplicationStore
    @EnvironmentObject var drawerOrderStore: DrawerOrderStore
    @EnvironmentObject var settingsStore: AppSettingsStore
    /// 拖卡进抽屉的投放反馈：手指压在投放区时胶囊放大 + 高亮描边。
    @EnvironmentObject var dragController: DragController
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DockThemeTokens { .resolved(for: colorScheme) }
    /// 右键胶囊 → 弹钨极菜单。胶囊是设置的**主要后路入口**：它恒在、位置固定、尺寸等于面板高度，
    /// 而且是钨极自己的部件（不属于任何 app），不像任务条底板那样只剩几条缝可点。
    var onRequestTaskbarMenu: (NSEvent, NSView) -> Void = { _, _ in }
    /// 底板走不走原生 Liquid Glass。**显式传入、无默认值**（同 `scale` / `hoverStyle`）——
    /// 胶囊是另一棵长期存活的 hosting 根视图，漏传就会出现「条是玻璃、紧挨着的胶囊还是
    /// 毛玻璃」这种一眼可见的不一致。
    let usesLiquidGlass: Bool
    /// Toggles the full drawer: the bottom-trailing cell, and any cell that holds no app.
    let action: () -> Void
    /// An app cell dispatched an "open" (launch / unhide): an open drawer closes, exactly as
    /// after a tap inside it. No default — an omission would leave the drawer open.
    let onPrimaryAction: () -> Void

    /// Cells are numbered row-major, 0...3; the last one is the expand cell.
    @State private var hoveredCell: Int?
    /// Press feedback per cell: a pure view-level signal, never fed to planner / frontmost.
    @State private var pressedCell: Int?
    /// Which page of the drawer the capsule shows; per capsule, so per screen.
    @StateObject private var pager = DrawerCapsulePager()

    private static let expandCell = DrawerCapsulePreviewMetrics.columns * DrawerCapsulePreviewMetrics.columns - 1

    private var iconSize: CGFloat { DrawerCapsulePreviewMetrics.iconSize * dockScale }
    private var gridSpacing: CGFloat { DrawerCapsulePreviewMetrics.gridSpacing * dockScale }

    /// Every visible drawer app in drawer order: the capsule pages through all of them.
    private var memberIDs: [String] {
        let placements = AppMembershipProjection.drawerMembers(drawerIDs: drawerStore.bundleIDs)
        let ordered = drawerOrderStore.reconciled(members: placements)
        return AppMembershipProjection.visibleDrawerIDs(
            drawerIDs: ordered,
            keptIDs: keptAppStore.bundleIDs,
            runningIDs: runningApplicationStore.runningBundleIDs
        )
    }

    private var capsuleSide: CGFloat { settingsStore.dockPanelHeight.metrics.capsuleWidth }

    /// 胶囊是**另一棵**长期存活的 NSHostingView 根视图，必须自己观察同一个 store，
    /// 否则换档时任务条变了、胶囊里的四宫格还停在旧尺寸。
    private var dockScale: CGFloat { settingsStore.dockPanelHeight.scale }

    /// 拖动时 hover 让位给拖入反馈：draggingPayload 非空则不弹（drag 优先）。
    private var hoverEnabled: Bool { !isPanelHeightResizing && dragController.draggingPayload == nil }

    var body: some View {
        let ids = memberIDs
        let pageCount = DrawerCapsulePaging.pageCount(memberCount: ids.count)
        let page = DrawerCapsulePaging.clampedPage(pager.page, pageCount: pageCount)
        let apps = DrawerCapsulePaging.apps(page: page, members: ids)
        return ZStack {
            DockPanelBackdrop(theme: theme,
                              cornerRadius: DockShape.panelCornerRadius * dockScale,
                              usesLiquidGlass: usesLiquidGlass,
                              matchesDockRefraction: true)

            // Hover and press feedback move only the cell under the pointer; the outer frame
            // (backdrop + rim) stays still.
            if ids.isEmpty {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 20 * dockScale, weight: .medium))
                    .foregroundStyle(theme.capsuleGlyph.color)
                    .cellFeedback(hovered: hoverEnabled && hoveredCell != nil, pressed: pressedCell != nil)
            } else {
                pagedPreview(ids: ids, pageCount: pageCount, page: page)
            }
        }
        .dockPanelRim(cornerRadius: DockShape.panelCornerRadius * dockScale,
                      style: theme.panelRimStyle,
                      lineWidth: theme.panelRimLineWidth,
                      usesLiquidGlass: usesLiquidGlass)
        // 拖卡悬到胶囊上：**微微发光 + 极轻微放大**（去掉原来生硬的白圈描边,owner 2026-06-21）。
        .scaleEffect(dragController.isOverStashZone ? 1.04 : 1.0)
        .dockGlow(theme.capsuleStashGlow, radius: 5, active: dragController.isOverStashZone)
        .animation(.easeInOut(duration: DrawerAnimation.duration), value: dragController.isOverStashZone)
        .dockShadow(theme.stripShadow,
                    visible: DockLiquidGlassConfiguration.stripShadowVisible(
                        usesLiquidGlass: usesLiquidGlass,
                        usesSystemVariant: DockGlassPresentation.usesSystemVariant))
        .padding(PanelCoordinator.shadowPadding)
        // The hit cells split the whole padded frame into quadrants, so each target is as large
        // as the capsule allows and reaches the screen edge.
        .overlay(hitGrid(apps: apps))
        // Takes scroll events only (see `DrawerCapsuleScrollView.hitTest`); clicks fall through.
        .overlay(DrawerCapsuleScrollReceiver(enabled: hoverEnabled && pageCount > 1) { event in
            switch event {
            case .step(let direction): pager.step(direction, pageCount: pageCount)
            case .drag(let points): pager.drag(points: points, side: capsuleSide)
            case .dragEnded: pager.endDrag(pageCount: pageCount)
            }
        })
        // The three slots are worth their fixed places: once the pointer has left, the capsule
        // goes back to the first page.
        .onChange(of: hoveredCell == nil) { away in
            if away { pager.scheduleReturn() } else { pager.cancelReturn() }
        }
        // MenuHostNSView 只认右键 / Control-click，左键一律返回 nil 穿透下去，
        // 所以左键仍落到上面的格子；右键在任何一格都是钨极菜单（设置的后路入口不缩小）。
        .overlay(NativeMenuHost(popUpHandler: onRequestTaskbarMenu))
    }

    // MARK: Preview

    /// All pages stacked vertically and slid as one column behind the capsule's own outline.
    private func pagedPreview(ids: [String], pageCount: Int, page: Int) -> some View {
        let side = capsuleSide
        let position = DrawerCapsulePaging.displayedPosition(page: page, drag: pager.drag, pageCount: pageCount)
        return VStack(spacing: 0) {
            ForEach(Array(0..<pageCount), id: \.self) { index in
                previewGrid(apps: DrawerCapsulePaging.apps(page: index, members: ids),
                            more: DrawerCapsulePaging.more(page: index, members: ids),
                            isCurrent: index == page)
                    .frame(width: side, height: side)
            }
        }
        .offset(y: -position * side)
        .frame(width: side, height: side, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: DockShape.panelCornerRadius * dockScale, style: .continuous))
    }

    private func previewGrid(apps: [String], more: [String], isCurrent: Bool) -> some View {
        let columns = DrawerCapsulePreviewMetrics.columns
        return VStack(spacing: gridSpacing) {
            ForEach(0..<columns, id: \.self) { row in
                HStack(spacing: gridSpacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        cellVisual(row * columns + column, apps: apps, more: more, isCurrent: isCurrent)
                    }
                }
            }
        }
    }

    /// Hover and press belong to the resting page only; the other pages are just passing by.
    @ViewBuilder
    private func cellVisual(_ index: Int, apps: [String], more: [String], isCurrent: Bool) -> some View {
        if index < apps.count {
            DrawerCapsuleAppIcon(bundleID: apps[index],
                                 size: iconSize,
                                 bounceHeight: 3 * dockScale,
                                 isLaunching: runtime.launchingBundleIDs.contains(apps[index]))
                .cellFeedback(hovered: isCurrent && hoverEnabled && hoveredCell == index,
                              pressed: isCurrent && pressedCell == index)
        } else if index == Self.expandCell {
            // An app-less cell also expands the drawer, so its feedback shows here.
            expandVisual(more: more)
                .cellFeedback(hovered: isCurrent && hoverEnabled && hoveredCell.map { $0 >= apps.count } == true,
                              pressed: isCurrent && pressedCell.map { $0 >= apps.count } == true)
        } else {
            Color.clear.frame(width: iconSize, height: iconSize)
        }
    }

    @ViewBuilder
    private func expandVisual(more: [String]) -> some View {
        if more.isEmpty {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: iconSize * 0.8, weight: .medium))
                .foregroundStyle(theme.capsuleGlyph.color)
                .frame(width: iconSize, height: iconSize)
        } else {
            let columns = DrawerCapsulePreviewMetrics.miniColumns
            let size = DrawerCapsulePreviewMetrics.miniIconSize * dockScale
            let spacing = DrawerCapsulePreviewMetrics.miniSpacing * dockScale
            VStack(spacing: spacing) {
                ForEach(0..<columns, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < more.count {
                                Image(nsImage: AppIconResolver.icon(for: more[index]))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: size, height: size)
                                    .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
                            } else {
                                Color.clear.frame(width: size, height: size)
                            }
                        }
                    }
                }
            }
            .frame(width: iconSize, height: iconSize)
        }
    }

    // MARK: Hit cells

    private func hitGrid(apps: [String]) -> some View {
        let columns = DrawerCapsulePreviewMetrics.columns
        return VStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        hitCell(index, bundleID: index < apps.count ? apps[index] : nil)
                    }
                }
            }
        }
    }

    private func hitCell(_ index: Int, bundleID: String?) -> some View {
        let isLaunching = bundleID.map { runtime.launchingBundleIDs.contains($0) } ?? false
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { hoveredCell = index } else if hoveredCell == index { hoveredCell = nil }
            }
            .onTapGesture {
                if let bundleID { activate(bundleID) } else { action() }
            }
            // A tap during a launch session is a no-op, so it gets no press feedback either.
            .chipPressGesture(
                isPressed: Binding(
                    get: { pressedCell == index },
                    set: { pressed in
                        if pressed { pressedCell = index } else if pressedCell == index { pressedCell = nil }
                    }),
                isEnabled: !isLaunching
            )
            .help(bundleID.map { AppDisplayNameResolver.displayName(for: $0) } ?? "")
    }

    /// Same default tap as a drawer icon: launch / bring forward / hide when frontmost.
    private func activate(_ bundleID: String) {
        guard !runtime.launchingBundleIDs.contains(bundleID) else { return }
        let finderHasRealWindow = FinderTaskbarPolicy.isFinder(bundleID)
            && StripItem.items(from: runtime.snapshot).contains {
                $0.bundleIdentifier == bundleID && !$0.isAppLevelFallback
            }
        LauncherChip.performDefaultTap(
            bundleID: bundleID,
            isRunning: runningApplicationStore.isRunning(bundleID),
            finderHasRealWindow: finderHasRealWindow,
            launch: { if runtime.beginLaunch(bundleID) { onPrimaryAction() } },
            onOpen: onPrimaryAction
        )
    }
}

private extension View {
    /// Hover grows the cell in place, press dips it; both settle back exactly.
    func cellFeedback(hovered: Bool, pressed: Bool) -> some View {
        scaleEffect(hovered ? 1.1 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .chipPressScale(pressed)
    }
}

// MARK: - Capsule Paging

/// Where the capsule rests (`page`) and how far a live trackpad gesture has pulled it (`drag`).
/// The page is not clamped here — the member list changes underneath it — the view clamps on read.
@MainActor
final class DrawerCapsulePager: ObservableObject {
    @Published private(set) var page = 0
    @Published private(set) var drag: CGFloat = 0
    private var returnTimer: Timer?

    private static let turn = Animation.spring(response: 0.36, dampingFraction: 0.84)
    private static let returnHome = Animation.spring(response: 0.5, dampingFraction: 0.9)
    private static let returnDelay: TimeInterval = 3

    deinit { returnTimer?.invalidate() }

    /// A wheel notch: one page, animated.
    func step(_ direction: Int, pageCount: Int) {
        let target = DrawerCapsulePaging.clampedPage(
            DrawerCapsulePaging.clampedPage(page, pageCount: pageCount) + direction, pageCount: pageCount)
        withAnimation(Self.turn) {
            page = target
            drag = 0
        }
    }

    /// Trackpad travel follows the fingers frame by frame, so it is never animated.
    func drag(points: CGFloat, side: CGFloat) {
        guard side > 0, points.isFinite else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag = min(max(drag - points / side, -1), 1)
        }
    }

    func endDrag(pageCount: Int) {
        let target = DrawerCapsulePaging.settledPage(page: page, drag: drag, pageCount: pageCount)
        withAnimation(Self.turn) {
            page = target
            drag = 0
        }
    }

    func scheduleReturn() {
        returnTimer?.invalidate()
        guard page != 0 else { return }
        let timer = Timer(timeInterval: Self.returnDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.returnTimer = nil
                withAnimation(Self.returnHome) {
                    self.page = 0
                    self.drag = 0
                }
            }
        }
        returnTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancelReturn() {
        returnTimer?.invalidate()
        returnTimer = nil
    }
}

enum DrawerCapsuleScrollEvent {
    /// A wheel notch: -1 = previous page, 1 = next.
    case step(Int)
    /// Trackpad travel in points, in the system's content direction.
    case drag(CGFloat)
    case dragEnded
}

struct DrawerCapsuleScrollReceiver: NSViewRepresentable {
    let enabled: Bool
    let onEvent: (DrawerCapsuleScrollEvent) -> Void

    func makeNSView(context: Context) -> DrawerCapsuleScrollView { DrawerCapsuleScrollView() }

    func updateNSView(_ view: DrawerCapsuleScrollView, context: Context) {
        view.onEvent = onEvent
        view.enabled = enabled
    }

    static func dismantleNSView(_ view: DrawerCapsuleScrollView, coordinator: ()) { view.finishTracking() }
}

final class DrawerCapsuleScrollView: NSView {
    var onEvent: (DrawerCapsuleScrollEvent) -> Void = { _ in }
    var enabled = true {
        didSet { if oldValue && !enabled { finishTracking() } }
    }
    private var isTracking = false
    private var lastStepTime: TimeInterval = 0
    private var watchdog: Timer?

    /// Fast wheel spins turn several pages, but never faster than one page per interval.
    private static let stepInterval: TimeInterval = 0.12
    /// A gesture whose end never arrives (the pointer left the capsule mid-swipe) still settles.
    private static let trackingTimeout: TimeInterval = 0.3

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard enabled, super.hitTest(point) != nil,
              let event = NSApp.currentEvent, event.type == .scrollWheel else { return nil }
        // End events carry zero deltas and still belong to this gesture.
        return abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? self : nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard enabled else { return }
        // Paging settles on its own spring; the system's momentum tail would turn a second page.
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.isEmpty {
            let delta = event.scrollingDeltaY
            guard delta != 0, event.timestamp - lastStepTime >= Self.stepInterval else { return }
            lastStepTime = event.timestamp
            onEvent(.step(delta > 0 ? -1 : 1))
            return
        }
        if event.phase.contains(.began) { isTracking = true }
        guard isTracking else { return }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            finishTracking()
            return
        }
        if event.scrollingDeltaY != 0 { onEvent(.drag(event.scrollingDeltaY)) }
        watchdog?.invalidate()
        let timer = Timer(timeInterval: Self.trackingTimeout, repeats: false) { [weak self] _ in
            self?.finishTracking()
        }
        watchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func finishTracking() {
        watchdog?.invalidate()
        watchdog = nil
        guard isTracking else { return }
        isTracking = false
        onEvent(.dragEnded)
    }

    deinit { watchdog?.invalidate() }
}

// MARK: - Capsule App Icon

/// One directly clickable app in the capsule. Owns only the launch bounce; hover and press
/// are applied by the capsule, which owns the hit cells.
private struct DrawerCapsuleAppIcon: View {
    let bundleID: String
    let size: CGFloat
    let bounceHeight: CGFloat
    /// Runtime-owned launch session state, rendered only (same contract as `LauncherChip`).
    let isLaunching: Bool

    @State private var bounceUp = false
    @State private var bounceTimer: Timer?

    var body: some View {
        Image(nsImage: AppIconResolver.icon(for: bundleID))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .offset(y: bounceUp ? -bounceHeight : 0)
            .animation(.easeInOut(duration: 0.25), value: bounceUp)
            .onAppear { if isLaunching { startBounce() } }
            .onDisappear { stopBounce() }
            .onChange(of: isLaunching) { launching in
                if launching { startBounce() } else { stopBounce() }
            }
    }

    /// Finite legs scheduled by a common-mode timer, as in `LauncherChip`: a hover or layout
    /// transaction cannot turn the bounce into one that outlives the launch.
    private func startBounce() {
        guard bounceTimer == nil else { return }
        bounceUp = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in bounceUp.toggle() }
        timer.tolerance = 0.02
        bounceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopBounce() {
        bounceTimer?.invalidate()
        bounceTimer = nil
        bounceUp = false
    }
}

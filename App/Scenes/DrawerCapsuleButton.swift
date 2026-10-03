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

    private static let expandCell = DrawerCapsulePreviewMetrics.columns * DrawerCapsulePreviewMetrics.columns - 1

    private var iconSize: CGFloat { DrawerCapsulePreviewMetrics.iconSize * dockScale }
    private var gridSpacing: CGFloat { DrawerCapsulePreviewMetrics.gridSpacing * dockScale }

    private var previewIDs: [String] {
        let placements = AppMembershipProjection.drawerMembers(drawerIDs: drawerStore.bundleIDs)
        let ordered = drawerOrderStore.reconciled(members: placements)
        return AppMembershipProjection.drawerPreview(
            drawerIDs: ordered,
            keptIDs: keptAppStore.bundleIDs,
            runningIDs: runningApplicationStore.runningBundleIDs,
            limit: DrawerCapsulePreviewMetrics.limit
        )
    }

    /// 胶囊是**另一棵**长期存活的 NSHostingView 根视图，必须自己观察同一个 store，
    /// 否则换档时任务条变了、胶囊里的四宫格还停在旧尺寸。
    private var dockScale: CGFloat { settingsStore.dockPanelHeight.scale }

    /// 拖动时 hover 让位给拖入反馈：draggingPayload 非空则不弹（drag 优先）。
    private var hoverEnabled: Bool { !isPanelHeightResizing && dragController.draggingPayload == nil }

    var body: some View {
        let ids = previewIDs
        let apps = Array(ids.prefix(DrawerCapsulePreviewMetrics.appSlots))
        let more = Array(ids.dropFirst(DrawerCapsulePreviewMetrics.appSlots))
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
                previewGrid(apps: apps, more: more)
                    .padding(DrawerCapsulePreviewMetrics.gridPadding * dockScale)
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
        // MenuHostNSView 只认右键 / Control-click，左键一律返回 nil 穿透下去，
        // 所以左键仍落到上面的格子；右键在任何一格都是钨极菜单（设置的后路入口不缩小）。
        .overlay(NativeMenuHost(popUpHandler: onRequestTaskbarMenu))
    }

    // MARK: Preview

    private func previewGrid(apps: [String], more: [String]) -> some View {
        let columns = DrawerCapsulePreviewMetrics.columns
        return VStack(spacing: gridSpacing) {
            ForEach(0..<columns, id: \.self) { row in
                HStack(spacing: gridSpacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        cellVisual(row * columns + column, apps: apps, more: more)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellVisual(_ index: Int, apps: [String], more: [String]) -> some View {
        if index < apps.count {
            DrawerCapsuleAppIcon(bundleID: apps[index],
                                 size: iconSize,
                                 bounceHeight: 3 * dockScale,
                                 isLaunching: runtime.launchingBundleIDs.contains(apps[index]))
                .cellFeedback(hovered: hoverEnabled && hoveredCell == index, pressed: pressedCell == index)
        } else if index == Self.expandCell {
            // An app-less cell also expands the drawer, so its feedback shows here.
            expandVisual(more: more)
                .cellFeedback(hovered: hoverEnabled && hoveredCell.map { $0 >= apps.count } == true,
                              pressed: pressedCell.map { $0 >= apps.count } == true)
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

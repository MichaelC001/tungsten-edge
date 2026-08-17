import AppKit
import SwiftUI

// MARK: - 全屏载体视图（从 DragController.swift 拆出：它牵 ChipView/PinnedFolderChip 等 UI 依赖,
// 拆出去让 DragController 可被测试 target 本地编译）

/// 铺在载体面板上的浮动副本：跟着 `DragController.globalLocation` 走，点击穿透。按来源选画法。
struct DragCarrierView: View {
    @ObservedObject var controller: DragController
    /// 文件夹 chip 副本的封面来源（PanelCoordinator 的 carrierFactory 注入）。
    @EnvironmentObject var folderCoverStore: PinnedFolderCoverStore
    /// 载体是**第三棵**长期存活的根视图（另两棵是任务条和胶囊），必须自己观察同一个 store：
    /// 载体尺寸要和它离开的那个 chip 一致，否则起拖瞬间会跳大小。
    @EnvironmentObject var settingsStore: AppSettingsStore

    /// 来自任务条的载体用档位缩放；**未转正的抽屉图标不缩**——它离开的是抽屉，抽屉本轮不随档位缩放。
    private var dockScale: CGFloat { settingsStore.dockSize.scale }
    /// 载体不可命中、且三处都传 `forceHover: false`，两档渲染其实相同；跟着 store 走只为自洽，
    /// 免得以后有人打开 forceHover 时这里悄悄留一份写死的档位。
    private var hoverStyle: HoverStyle { settingsStore.hoverStyle }

    private let theme = DockThemeTokens.standard

    var body: some View {
        if let p = controller.draggingPayload {
            // 转正进任务条后就是在条内重排,**不缩小**（保持 1.05,与条内载体一致）；只有"未转正且命中投放区"
            // （任务条卡悬胶囊 / 抽屉图标悬任务条但还没转正）才缩 0.82。动画跟 shrink 走,0.82↔1.05 平滑(Codex 三审 P2)。
            let shrink = controller.isOverDropZone && !controller.isConvertedToStrip
            content(p)
                .scaleEffect(shrink ? 0.82 : 1.05)
                .animation(.easeOut(duration: 0.12), value: shrink)
                .position(controller.carrierPosition())
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(_ p: DragPayload) -> some View {
        // 抽屉拖回任务条·转正后:载体改画**代表卡**整张(与条内载体同款),让"拖回来"和"条内拖动"观感一致。
        // 代表卡由 DockStripView 在窗口卡实体化后写入;未实体化前 nil → 仍按 visualKind 画(抽屉里就是小图标)。
        if let rep = controller.convertedRepresentative {
            // 载体不弹悬停气泡：它是跟着鼠标飞的浮动副本，不可命中，弹了也只会挡住投放目标。
            // 显式写空实现而不是靠默认值——见 `ChipView.onWindowTitleTooltipEvent` 的注释。
            ChipView(item: rep, scale: dockScale, hoverStyle: hoverStyle, showRunningDot: true, forceHover: false,
                     onWindowTitleTooltipEvent: { _ in })
                .dockShadow(theme.carrierShadow)
        } else {
            switch p.visualKind {
            case .stripChip:
                if let item = p.item {
                    // forceHover: false —— 悬停态会在图标下方带出 app 名,拖动时不想要（owner 2026-06-21）。
                    // 非悬停态 = 干净的大图标(单窗口卡),贴近抽屉拖动的观感。代价是起拖瞬间图标略放大,可接受。
                    ChipView(item: item, scale: dockScale, hoverStyle: hoverStyle, showRunningDot: true, forceHover: false,
                             onWindowTitleTooltipEvent: { _ in })
                        .dockShadow(theme.carrierShadow)
                }
            case .drawerIcon:
                // 抽屉图标本轮有意不跟任务条档位缩放（2026-07-30 owner 定的范围外项），
                // 恒 0.7 与抽屉里的 LauncherChip 同尺寸——显式写出来，不靠默认值。
                DrawerDragIconView(bundleID: p.bundleID, scale: 0.7)
                    .dockShadow(theme.carrierShadow)
            case .keptAppIcon:
                // 保留应用图标住在任务条里，载体跟任务条档位走（不是抽屉的 0.7）。
                DrawerDragIconView(bundleID: p.bundleID, scale: dockScale)
                    .dockShadow(theme.carrierShadow)
            case .messagingIcon:
                // 消息区 chip 在条内是任务条档位缩放的 app 图标，载体同尺寸,免得起拖瞬间跳大小。
                DrawerDragIconView(bundleID: p.bundleID, scale: dockScale)
                    .dockShadow(theme.carrierShadow)
            case .folderChip:
                // 文件夹 chip 副本：复用 PinnedFolderChip 视觉（封面从 coverStore 取）,闭包全空——
                // 载体面板 ignoresMouseEvents,菜单/点击永远不会触发。拖离任务条可见范围时淡出+
                // 略放大,给「松手即移除固定」一个实时视觉反馈（owner 2026-07-06 反馈）。
                let aboutToRemove = controller.folderDragZone == .outsideStrip
                PinnedFolderChip(path: p.id,
                                 cover: folderCoverStore.covers[p.id],
                                 sortOrder: .default,
                                 onTap: {}, onPreview: {}, onOpenInFinder: {}, onAddFolder: {}, onRemove: {},
                                 onSetSortOrder: { _ in },
                                 scale: dockScale,
                                 hoverStyle: hoverStyle)
                    .dockShadow(theme.carrierShadow)
                    .opacity(aboutToRemove ? 0.35 : 1.0)
                    .scaleEffect(aboutToRemove ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: aboutToRemove)
            }
        }
    }
}

/// 抽屉拖动副本：只画 app 图标，不带 `LauncherChip` 的菜单/弹跳/tap（Codex 二审：载体要轻）。
/// 尺寸与抽屉里 `LauncherChip`（scale 0.7）一致，免得起拖瞬间变大小。
struct DrawerDragIconView: View {
    let bundleID: String
    /// 档位系数（抽屉恒定 0.7，任务条内传 `DockSize.scale`）。**故意不给默认值**——
    /// 漏传必须是编译错误，见 AGENTS《Taskbar Size Tiers》。
    let scale: CGFloat

    private let theme = DockThemeTokens.standard

    var body: some View {
        // 拖动浮动副本必须与条上原卡逐像素同尺寸，否则松手前后会跳一下。
        let iconSize = ChipPillMetrics.bareIconSlot * scale
        return Image(nsImage: AppIconResolver.icon(for: bundleID))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: iconSize / 4, style: .continuous))
            .dockShadow(theme.iconShadow)
            .frame(width: ChipPillMetrics.cardWidth * scale,
                   height: ChipPillMetrics.chipHeight * scale)
    }
}

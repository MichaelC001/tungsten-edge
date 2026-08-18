import AppKit
import SwiftUI

// MARK: - 全屏载体视图（从 DragController.swift 拆出：它牵 ChipView/PinnedFolderChip 等 UI 依赖,
// 拆出去让 DragController 可被测试 target 本地编译）

/// 浮动副本**长什么样**，点击穿透。按来源选画法。
///
/// **它不再管自己在哪。** 位置由 `DragController` 直接设这块宿主视图的 frame（AppKit 侧，
/// 收到鼠标事件的同一轮 run loop 里同步完成）。原来是每动一下鼠标就让 SwiftUI 重画一次
/// `.position`，实测拖快了副本会落在光标后面一百多 pt（owner 2026-08-18 的连拍）——
/// 渲染管线本来就跟不上鼠标事件的频率，这条路走不通。
struct DragCarrierView: View {
    @ObservedObject var controller: DragController
    /// 文件夹 chip 副本的封面来源（PanelCoordinator 的 carrierFactory 注入）。
    @EnvironmentObject var folderCoverStore: PinnedFolderCoverStore
    /// 载体是**第三棵**长期存活的根视图（另两棵是任务条和胶囊），必须自己观察同一个 store：
    /// 载体尺寸要和它离开的那个 chip 一致，否则起拖瞬间会跳大小。
    @EnvironmentObject var settingsStore: AppSettingsStore

    /// 来自任务条的载体用档位缩放；**未转正的抽屉图标不缩**——它离开的是抽屉，抽屉本轮不随档位缩放。
    private var dockScale: CGFloat { settingsStore.dockSize.scale }
    /// 载体不可命中、三处都传 `isHovered: false`，两档渲染其实相同；跟着 store 走只为自洽，
    /// 免得以后这里悄悄留一份写死的档位。
    private var hoverStyle: HoverStyle { settingsStore.hoverStyle }

    private let theme = DockThemeTokens.standard

    var body: some View {
        // 宿主视图是**固定尺寸**的（`DragLandingPlan.carrierHostSize`），副本在里面居中。
        // 刻意不按内容量尺寸：量尺寸要等 SwiftUI 先把新载荷布局出来，那又是一次时序赌博，
        // 而这块宿主本来就是透明、不吃鼠标的，大一点没有任何代价。
        Group {
            if let p = controller.draggingPayload {
                // 转正进任务条后就是在条内重排,**不缩小**（保持 1.05,与条内载体一致）；只有"未转正且命中投放区"
                // （任务条卡悬胶囊 / 抽屉图标悬任务条但还没转正）才缩 0.82。
                let shrink = controller.isOverDropZone && !controller.isConvertedToStrip
                PickUpCarrier(shrunk: shrink,
                              onRendered: { controller.markCarrierRendered() }) {
                    content(p, representative: controller.convertedRepresentative)
                }
                // **每次拖动都必须是一个全新的视图**，否则 SwiftUI 复用它、`onAppear` 不再触发，
                // 「副本画好了」那一声就永远不来 —— 条上那格只能等兜底计时器，
                // 这段时间原位和手里各画一个 = owner 看到的上下重影。
                .id(controller.dragSessionID)
            } else if let landing = controller.landing {
                // 松手之后的归位飞行：**只负责缩放**，位移由 controller 动宿主视图的 frame。
                // 载荷与代表卡都从 `landing` 里取——此刻 controller 上那些字段已经清空了
                //（收尾必须先跑完，store 才是最终状态）。
                LandingCarrier(landing: landing) { payload, rep in
                    content(payload, representative: rep)
                }
                .id(landing.token)   // 连着两次拖动不复用同一份动画状态
            }
        }
        .frame(width: DragLandingPlan.carrierHostSize.width,
               height: DragLandingPlan.carrierHostSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ p: DragPayload, representative: StripItem?) -> some View {
        // 抽屉拖回任务条·转正后:载体改画**代表卡**整张(与条内载体同款),让"拖回来"和"条内拖动"观感一致。
        // 代表卡由 DockStripView 在窗口卡实体化后写入;未实体化前 nil → 仍按 visualKind 画(抽屉里就是小图标)。
        if let rep = representative {
            // 载体不参与悬停：它是跟着鼠标飞的浮动副本，不可命中，条上那块跟踪区也报不到它。
            // 显式写 `isHovered: false` 而不是靠默认值——那个属性刻意没有默认值。
            ChipView(item: rep, scale: dockScale, hoverStyle: hoverStyle,
                     isHovered: false, showRunningDot: true)
                .dockShadow(theme.carrierShadow)
        } else {
            switch p.visualKind {
            case .stripChip:
                if let item = p.item {
                    // 非悬停态 = 干净的大图标(单窗口卡),贴近抽屉拖动的观感。代价是起拖瞬间图标略放大,可接受。
                    ChipView(item: item, scale: dockScale, hoverStyle: hoverStyle,
                             isHovered: false, showRunningDot: true)
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
                                 hoverStyle: hoverStyle,
                                 isHovered: false)
                    .dockShadow(theme.carrierShadow)
                    .opacity(aboutToRemove ? 0.35 : 1.0)
                    .scaleEffect(aboutToRemove ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: aboutToRemove)
            }
        }
    }
}

/// 起拖那一小段：载体**从条上那张卡当时的样子接手**，再长到拎在手里的 1.05。
///
/// 为什么不是直接 1.05（owner 2026-08-18 报「选中图标的一瞬间卡顿」）：按下去的时候
/// `ChipPressFeedback` 已经把那张卡缩到了 0.93，而载体一出现就是 1.05——中间 13% 的
/// 尺寸差是**跳**过去的，读起来就是起手一顿。从 0.93 接手再长大，交接才是连续的。
///
/// `onRendered` 是"载体已经画出来了"的信号：条上那张卡要等到这一刻才藏，
/// 否则会出现两边都没有的空档（见 `DragController.hiddenSlotPayload`）。
private struct PickUpCarrier<Content: View>: View {
    let shrunk: Bool
    /// 「内容已经构建出来了」的回报。条上那格要等这一声才允许空出来
    /// ——理由见 `DragController.markCarrierRendered`。
    let onRendered: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var pickedUp = false

    private var scale: CGFloat {
        if shrunk { return DragLandingPlan.dropZoneScale }
        return pickedUp ? DragLandingPlan.carriedScale : ChipPressDecision.pressedScale
    }

    var body: some View {
        content()
            .scaleEffect(scale)
            .animation(.easeOut(duration: 0.12), value: scale)
            .onAppear {
                pickedUp = true
                onRendered()
            }
    }
}

/// 归位飞行的那一小段：出现时就以动画滑向终点。
///
/// **必须是独立的 `View` 带自己的 `@State`**，不能在 controller 里 `withAnimation` 翻一个已发布的标志——
/// 那样要赌 SwiftUI 已经把起点那一帧画出来了；`onAppear` 是有保证的。
private struct LandingCarrier<Content: View>: View {
    let landing: DragController.Landing
    @ViewBuilder let content: (DragPayload, StripItem?) -> Content

    @State private var arrived = false

    private var scale: CGFloat { arrived ? landing.flight.toScale : landing.flight.fromScale }

    var body: some View {
        // **只做缩放**：位移已经交给 AppKit（`DragController.placeCarrier`）。两边用同一条曲线
        // 和同一个时长（`landing.flight.duration`，按距离算），所以看起来仍是一次运动。
        // 定时长的 ease-out 而不是 spring，理由见 `DragLandingPlan.curve`
        //（spring 在 response 时刻还没停，会被收载体的计时器硬切成一次跳动）。
        let c = DragLandingPlan.curve
        let curve = Animation.timingCurve(c.c0x, c.c0y, c.c1x, c.c1y, duration: landing.flight.duration)
        return content(landing.payload, landing.representative)
            .scaleEffect(scale)
            .animation(curve, value: scale)
            .onAppear { arrived = true }
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

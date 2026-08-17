import AppKit
import SwiftUI

// MARK: - DockThemeTokens 的 SwiftUI / AppKit 桥接
//
// 纯数值表在 `Core/Support/DockThemeTokens.swift`（不 import SwiftUI，因此可被单测精确冻结）。
// 这里只做「数值 → Color / Material / 修饰符」的翻译，不含任何取值判断。
//
// 用法：需要上色的视图加
//     private let theme = DockThemeTokens.standard
// 然后读 `theme.xxx.color`。
//
// **只有一套值**（产品固定浅色，owner 2026-08-16 删掉深色模式），所以这里没有取值判断，
// 视图也不用再读 `colorScheme`。前提是 `AppDelegate` 无条件把 `NSApp.appearance` 钉成
// `.aqua`——毛玻璃与玻璃跟的是窗口外观、不看 SwiftUI 环境。

extension DockThemeTokens {
    /// 实际生效的材质：`DOCK_PANEL_MATERIAL` 覆盖 token 值（认不出的名字回落，不崩）。
    var effectivePanelMaterial: DockPanelMaterial {
        DockPanelMaterial.resolved(from: DockEffectSwitches.environment, fallback: panelMaterial)
    }

    /// 实际生效的背景饱和度。未开 → `1.0`（桥接层的 `dockBackdropSaturation` 会整个跳过修饰符）。
    /// 开了才用表里的候选值，也可以直接在环境变量里给一个数覆盖它。
    var effectiveBackdropSaturation: Double {
        DockEffectSwitches.saturation(from: DockEffectSwitches.environment, candidate: panelBackdropSaturation)
    }

    /// 实际生效的中转格瓷砖配色：`DOCK_SHELF_TILE=blue|graphite|light` 覆盖 token 值
    /// （认不出的名字回落到 `.blue`，不崩）。三档是同一个位置的互斥选项，现场换档不重编译。
    var effectiveShelfTile: DockShelfTileStyle {
        guard let raw = DockEffectSwitches.environment["DOCK_SHELF_TILE"] else { return shelfTile }
        return DockShelfTileStyle.resolve(raw)
    }

    /// 厚度层到底画不画：**先看开关**，再看纯条件（`drawsPanelThickness`，颜色与线宽都得非零）。
    /// 深色两层保险——候选值本来就是 0，开关打开也不画。
    var drawsEffectiveThickness: Bool {
        DockEffectSwitches.thicknessEnabled(from: DockEffectSwitches.environment) && drawsPanelThickness
    }
}

enum DockEffectSwitches {
    /// 读一次就固定——调参期间改环境变量重启一次即可，也避免一次会话里前后不一致。
    static let environment = ProcessInfo.processInfo.environment

    /// `DOCK_PANEL_SATURATION=1.25`。未设 / 非数字 / 超出合理范围 → `1.0`（= 不加滤镜）。
    /// 特例：`1` 也当"开，用表里的候选值"讲不通——数字就是倍数本身，`1` 就是不提饱和。
    /// 想用表里的候选值就写 `candidate`。
    static func saturation(from environment: [String: String], candidate: Double) -> Double {
        guard let raw = environment["DOCK_PANEL_SATURATION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else { return 1.0 }
        if raw == "candidate" { return candidate }
        guard let value = Double(raw), value > 0, value <= 5 else { return 1.0 }
        return value
    }

    /// `DOCK_PANEL_THICKNESS=1` 才开。其余一切（含未设、`0`、乱填）都是关。
    static func thicknessEnabled(from environment: [String: String]) -> Bool {
        environment["DOCK_PANEL_THICKNESS"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// 调参诊断：只有真的设了某个开关才打一行，打的是**解析后**的值——
    /// 名字或数字写错（被回落）当场就看得出来，不会拿着一张其实没生效的对照图瞎比。
    static func logActiveOverrides(material: DockPanelMaterial, saturation: Double, thickness: Bool) {
        if let raw = environment["DOCK_PANEL_MATERIAL"] {
            print("[panel] DOCK_PANEL_MATERIAL=\"\(raw)\" → 实际生效 \(material)")
        }
        if let raw = environment["DOCK_PANEL_SATURATION"] {
            print("[panel] DOCK_PANEL_SATURATION=\"\(raw)\" → 实际生效 \(saturation)")
        }
        if let raw = environment["DOCK_PANEL_THICKNESS"] {
            print("[panel] DOCK_PANEL_THICKNESS=\"\(raw)\" → 厚度层\(thickness ? "开" : "关")")
        }
    }
}

extension DockRGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// 悬停放大的动画曲线。**调参用的临时脚手架**——owner 挑定一条之后就把这个枚举拆掉、
/// 把选中的曲线写死回 `chipQuietHoverScale`（同药丸浓度那批候选的处理方式）。
///
/// 为什么需要挑：主线程实测在这 120ms 里**没有任何卡顿、没有重算、没有 relayout**，
/// 所以「不够流畅」不是被抢了资源，而是曲线本身——120ms 在 60Hz 下只有 7 帧，
/// 位移又只有 4pt，容易读成"跳"而不是"滑"。这类东西量不出来，只能上眼。
enum ChipHoverCurve: String {
    /// 现状：短促的减速曲线。
    case easeOut12
    /// 同样的减速，但拉长到 180ms —— 帧数多一半。
    case easeOut18
    /// 弹簧，收尾带一点点回弹。原生 Dock 的放大就是这一类手感。
    case spring

    static let current: ChipHoverCurve = {
        let raw = ProcessInfo.processInfo.environment["DOCK_HOVER_CURVE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "easeout18", "18": return .easeOut18
        case "spring": return .spring
        default: return .easeOut12
        }
    }()

    var animation: Animation {
        switch self {
        case .easeOut12: return .easeOut(duration: 0.12)
        case .easeOut18: return .easeOut(duration: 0.18)
        case .spring: return .spring(response: 0.28, dampingFraction: 0.72)
        }
    }
}

extension DockShelfTileStyle {
    /// 瓷砖的上→下渐变。`lifted` = 外部文件悬停命中，整块朝白提一点。
    func gradient(lifted: Bool) -> LinearGradient {
        let c = colors
        let amount = lifted ? Self.dropTargetLift : 0
        return LinearGradient(colors: [c.top.lightened(by: amount).color,
                                       c.bottom.lightened(by: amount).color],
                              startPoint: .top,
                              endPoint: .bottom)
    }

    var glyphColor: Color { colors.glyph.color }
}

extension DockTint {
    var color: Color {
        switch base {
        case .white: return Color.white.opacity(opacity)
        case .black: return Color.black.opacity(opacity)
        }
    }

    /// 同基色的全透明版本。
    /// **不要用 `Color.clear` 代替**：动画是在两个颜色之间插值，从 `.clear` 淡向一个白色描边
    /// 会在中途透出灰边；改造前的写法本来就是 `opacity(isActive ? 0.9 : 0)`。
    var transparent: Color { DockTint(base: base, opacity: 0).color }

    /// 按状态开关同一处着色（关 = 同基色全透明）。
    func color(active: Bool) -> Color { active ? color : transparent }
}

extension DockTintPair {
    /// - Parameter emphasized: 悬停中，或投放命中。
    func color(emphasized: Bool) -> Color {
        (emphasized ? self.emphasized : normal).color
    }

    func color(emphasisProgress rawProgress: Double) -> Color {
        let progress = min(max(rawProgress, 0), 1)
        let opacity = normal.opacity + (emphasized.opacity - normal.opacity) * progress
        return DockTint(base: normal.base, opacity: opacity).color
    }
}

extension DockPanelMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .popover: return .popover
        case .hudWindow: return .hudWindow
        case .menu: return .menu
        case .underWindowBackground: return .underWindowBackground
        case .sidebar: return .sidebar
        case .titlebar: return .titlebar
        case .selection: return .selection
        case .headerView: return .headerView
        case .fullScreenUI: return .fullScreenUI
        case .toolTip: return .toolTip
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .contentBackground: return .contentBackground
        case .underPageBackground: return .underPageBackground
        }
    }
}

// MARK: - 未验收效果的开关
//
// **默认值 = owner 已认可的观感；未验收的效果一律 opt-in。**
//
// 这条是 2026-07-30 订正出来的：玻璃探路当时做成了默认关 + `DOCK_LIQUID_GLASS=1` 才开，
// 但同一天加的提饱和与厚度层却默认生效了——同样是没验收的效果，两套标准。结果 owner
// 眼前的观感在他不知情的情况下偏离了他点过头的那一版，是他自己发现的。
//
// 所以下面三样统一 opt-in。调参时一次重启切一样，也顺带解决「三个变量叠一起归不了因」。
// 候选数值仍然只有一张表（`DockThemeTokens.light`），开关只决定用不用它。

extension DockThemeTokens {
    /// 面板描边：上沿亮、下沿暗，模拟来自上方的光（苹果原生玻璃的打光方向）。
    /// 深色两端同值 → 渐变退化成均匀色，与改造前的 `.strokeBorder(.white.opacity(0.15))` 逐像素一致。
    var panelRimStyle: LinearGradient {
        LinearGradient(colors: [panelRimTop.color, panelRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    /// 投放命中时换成实色整框；否则用上下渐变。
    func panelRimStyle(highlighted: Bool) -> AnyShapeStyle {
        highlighted ? AnyShapeStyle(panelRimHighlighted.color) : AnyShapeStyle(panelRimStyle)
    }

    func panelRimLineWidth(highlighted: Bool) -> CGFloat {
        highlighted ? panelRimHighlightedLineWidth : panelRimLineWidth
    }

    /// 玻璃厚度层：上内沿一条亮线（光从上方进入介质）+ 下内沿一道暗收（介质底部自阴影）。
    /// 画在材质**之上**、内容**之下**，是我们自己的像素——所以不受「拿不到窗口背后像素」
    /// 那条限制（折射与背景饱和度就是卡在那里）。
    ///
    /// 调用方必须先判 `drawsEffectiveThickness`（开关 + 纯条件）：深色与未开时整层不进视图树。
    @ViewBuilder
    func panelThicknessLayer(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerHighlight.color, panelInnerHighlight.transparent],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: panelInnerHighlightWidth
                )
                .blur(radius: panelInnerHighlightBlur)
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerShadow.transparent, panelInnerShadow.color],
                                   startPoint: .center, endPoint: .bottom),
                    lineWidth: panelInnerShadowWidth
                )
                .blur(radius: panelInnerShadowBlur)
        }
        // 模糊会溢出形状，必须裁回来，否则厚度层会糊到面板外面去。
        .clipShape(shape)
        // 纯装饰层，绝不能抢 chip 的点击（面板是 nonactivatingPanel，chip 全靠 onTapGesture）。
        .allowsHitTesting(false)
    }

    /// 标题胶囊的描边：同样是上亮下暗。
    /// - Parameter emphasized: 悬停中。
    func chipPillRimStyle(emphasized: Bool) -> LinearGradient {
        LinearGradient(colors: [chipPillRimTop.color(emphasized: emphasized), chipPillRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    func chipPillRimStyle(emphasisProgress: Double) -> LinearGradient {
        LinearGradient(
            colors: [chipPillRimTop.color(emphasisProgress: emphasisProgress), chipPillRimBottom.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// 安静档的悬停反馈：整块**轻微放大**。判据见 `HoverStyle.showsQuietHoverFeedback`。
    ///
    /// `scaleEffect` 是纯渲染变换：**不改布局尺寸**（这一档的底线就是"鼠标划过任务条不重排"），
    /// 也不影响 `.background` 里 GeometryReader 上报的投放命中矩形——`PinnedFolderChip`
    /// 的整块放大早就是这么做的，同一条既有结论。
    ///
    /// anchor 取 `.bottom`：条只有 54pt 高、卡片撑满条高，从中心放大会往下越出条外；
    /// 从底边顶起既留在条内，也更像原生 Dock 的放大方向。
    ///
    /// 动画用 `.animation(_:value:)`（值域限定），只有 `isActive` 变化时才动。
    /// `LauncherChip` 的启动弹跳有自己更内层的 `.animation(_:value: bounceUp)`，
    /// 内层优先，不会被这一层裹走——AGENTS 里「安静档不产生事务」防的就是弹跳被劫持。
    func chipQuietHoverScale(_ isActive: Bool) -> some View {
        self
            .scaleEffect(isActive ? ChipPillMetrics.quietHoverScale : 1, anchor: .bottom)
            .animation(ChipHoverCurve.current.animation, value: isActive)
    }

    /// 给毛玻璃底板加背景提饱和。**1.0 时整个修饰符都不挂**——`.saturation(1.0)` 虽是恒等，
    /// 但仍可能触发离屏渲染，多一层就可能破坏深色的逐像素冻结（同厚度层的理由）。
    @ViewBuilder
    func dockBackdropSaturation(_ amount: Double) -> some View {
        if amount == 1.0 { self } else { self.saturation(amount) }
    }

    /// 应用一个 `DockShadow`（x 恒为 0）。
    func dockShadow(_ shadow: DockShadow) -> some View {
        self.shadow(color: shadow.tint.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// 条件式光晕：`active` 为假时半径与不透明度都归零（等价于不画）。
    func dockGlow(_ tint: DockTint, radius: CGFloat, active: Bool) -> some View {
        self.shadow(color: tint.color(active: active), radius: active ? radius : 0)
    }
}

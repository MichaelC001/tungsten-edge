import AppKit
import SwiftUI

// MARK: - DockThemeTokens 的 SwiftUI / AppKit 桥接
//
// 纯数值表在 `Core/Support/DockThemeTokens.swift`（不 import SwiftUI，因此可被单测精确冻结）。
// 这里只做「数值 → Color / Material / 修饰符」的翻译，不含任何取值判断。
//
// 用法：需要上色的视图加
//     @Environment(\.colorScheme) private var colorScheme
//     private var theme: DockThemeTokens { .resolve(colorScheme) }
// 然后读 `theme.xxx.color`。
//
// 为什么不建 EnvironmentKey 注入：`colorScheme` 本身就是环境值，逐个 struct 自己读最省事，
// 也不用在 5 个宿主面板各写一遍注入。

extension DockThemeTokens {
    /// 唯一的取值入口。`colorScheme` 由各面板的 `NSHostingView` 从窗口 `effectiveAppearance`
    /// 继承（所有面板都没有覆写 `appearance`，所以就是系统当前外观），系统切换外观时自动重算。
    static func resolve(_ colorScheme: ColorScheme) -> DockThemeTokens {
        colorScheme == .dark ? .dark : .light
    }
}

extension AppearanceMode {
    /// 设到 `NSApp.appearance` 上；`nil` = 交还系统。
    ///
    /// 为什么是 `NSApp` 这一处、而不是 SwiftUI 的 `.preferredColorScheme()`：毛玻璃
    /// `DockVisualEffectView` 包的是 `NSVisualEffectView`，它跟**窗口**的
    /// `effectiveAppearance` 走、不看 SwiftUI 环境，所以 `.preferredColorScheme()` 只会翻
    /// 主题色而留下对不上的材质。而我们所有面板/窗口都没设过自己的 `appearance`，
    /// 会一路回落到 `NSApp.effectiveAppearance` —— 一处翻转就同时管住主题色、毛玻璃材质、
    /// 状态栏菜单，**以及之后才新建的面板**（抽屉、文件夹/中转站弹窗、tooltip、拖动载体
    /// 都是按需新建的）。也正因如此，三个长寿 hosting root 那条「各自 observe
    /// AppSettingsStore」的规矩在这条功能上不适用：变化是顺 AppKit 外观继承链下来的，
    /// 不是一个 SwiftUI 值，别为此去补注入。
    ///
    /// 状态栏图标不受影响：它是 template image，由菜单栏按系统外观自己染色。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
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
    /// 实际生效的材质：`DOCK_PANEL_MATERIAL` 覆盖 token 值（认不出的名字回落，不崩）。
    var effectivePanelMaterial: DockPanelMaterial {
        DockPanelMaterial.resolved(from: DockEffectSwitches.environment, fallback: panelMaterial)
    }

    /// 实际生效的背景饱和度。未开 → `1.0`（桥接层的 `dockBackdropSaturation` 会整个跳过修饰符）。
    /// 开了才用表里的候选值，也可以直接在环境变量里给一个数覆盖它。
    var effectiveBackdropSaturation: Double {
        DockEffectSwitches.saturation(from: DockEffectSwitches.environment, candidate: panelBackdropSaturation)
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

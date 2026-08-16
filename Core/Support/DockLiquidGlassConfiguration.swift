import CoreGraphics
import Foundation

enum DockLiquidGlassRenderPath: Equatable {
    case visualEffectFallback
    case layeredTaskbar
}

/// 液态玻璃底板的可调参数。
///
/// **这里只放「玻璃这块底板怎么画」，不放几何。** 面板高度、圆角、离屏底距一律来自
/// `DockSize.metrics` 与 `DockShape.panelCornerRadius`（`AGENTS.md`：几何的唯一来源）——
/// 玻璃自带第二套尺寸会让四档缩放失效，因为 `scale` 的定义本身就是 `panelHeight / 52`。
///
/// **也不放阴影。** 落地阴影由 SwiftUI 侧的 `.dockShadow(theme.stripShadow)` 画在内容窗口的
/// 20pt 透明边里；曾经试过改画到背景窗口的图层上，但那个窗口的 frame 正好等于底板本身，
/// 图层阴影画在窗口外会被整个裁掉 —— 净效果是玻璃态没有阴影。别再往回改。
struct DockLiquidGlassConfiguration: Equatable {
    let isEnabled: Bool
    /// `Glass.clear` 的灰色染色强度。玻璃本身太透，图标会认不出来（owner 2026-07-30 否掉
    /// 纯原生玻璃的原因），这一层是把通透度压回可用范围的主要手柄。
    let clearTintOpacity: Double
    /// 玻璃**之下**的一层加白。默认 0。
    let whiteOverlayOpacity: Double
    /// 背景窗口里那层压暗/提亮（按深浅色取黑或白）。默认 0。
    ///
    /// **只在背景窗口画一次。** 曾经内容窗口也叠了一层写死的黑，两处颜色还不一致
    /// （SwiftUI 侧恒为黑、背景窗口侧按外观切换），默认值 0 时看不出来，一调就露馅。
    let dimmingOpacity: Double
    /// 边缘高光：**均匀一圈**白色描边的 alpha。
    ///
    /// 默认值由实测反推（2026-08-16，深色壁纸）：原生底板亮度 81、边缘 148，钨极底板 84，
    /// 要打到同样的 148 需要 `α = (148 − 84) / (255 − 84) ≈ 0.375`。
    ///
    /// **这是「像不像原生」最贵重的一档。** 原生 Dock 靠这一圈把轮廓从背景里勾出来；
    /// 缺了它条会糊进背景、像直接刷在屏幕上，连圆角都显得比实际方
    /// （实测钨极圆角 16pt 其实比原生的 14pt 还大，但看着更方）。
    let borderOpacity: Double
    /// 描边宽度。原生实测最外那道是 1px @2x = **0.5pt**，比直觉细得多。
    let borderLineWidth: Double
    /// 紧贴外圈**内侧**再画一道更暗的，凑出原生那条两像素的亮边。
    ///
    /// 原生实测顶边剖面是 `148 → 120 → 81(底板)`：一个满像素 + 一个半档，共两像素。
    /// 只画一道时峰值一样是 148，但**视觉分量只有一半，肉眼就是「没原生亮」**
    /// （owner 2026-08-16 反馈，量出来才发现峰值其实早就对上了，差的是宽度）。
    /// 反推：底板 84 打到 120 需要 `α = (120 − 84) / (255 − 84) ≈ 0.21`。
    let borderInnerOpacity: Double
    /// 背景窗口里那层 `.menu` 材质的不透明度，用来在玻璃之外再补一点实心感。默认 0。
    let backgroundMaterialOpacity: Double
    /// 背景窗口的 WindowServer 模糊半径（SkyLight）。
    ///
    /// **必须画在与玻璃宿主分离的窗口上。** 直接给承载 SwiftUI glass 的同一个窗口设这个值，
    /// 会二次合成纵向光照（受控彩条实测：顶部/底部平均亮度从约 131/127 放大成 101/163）。
    let windowBlurRadius: Double
    /// 玻璃形状先外扩再内缩的量，给玻璃自己的边缘渲染留余量。
    let contentInset: Double
    /// 背景窗口根图层的黑底不透明度。**不是观感参数**：WindowServer 需要一块非零 alpha 的
    /// 形状才肯对这个窗口做背景模糊，这是给它的最小锚点。
    let backgroundPlateOpacity: Double

    func renderPath(
        isGlassAPIAvailable: Bool,
        isCompositeAvailable: Bool
    ) -> DockLiquidGlassRenderPath {
        guard isEnabled, isGlassAPIAvailable, isCompositeAvailable else {
            return .visualEffectFallback
        }
        return .layeredTaskbar
    }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        Self(
            isEnabled: trimmed(environment["DOCK_LIQUID_GLASS"]) == "1",
            clearTintOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_CLEAR_TINT"],
                range: 0 ... 1,
                fallback: 0.4
            ),
            whiteOverlayOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_WHITE_OVERLAY"],
                range: 0 ... 1,
                fallback: 0
            ),
            dimmingOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_DIMMING"],
                range: 0 ... 1,
                fallback: 0
            ),
            borderOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BORDER"],
                range: 0 ... 1,
                fallback: 0.375
            ),
            borderLineWidth: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BORDER_WIDTH"],
                range: 0 ... 4,
                fallback: 0.5
            ),
            borderInnerOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BORDER_INNER"],
                range: 0 ... 1,
                fallback: 0.21
            ),
            backgroundMaterialOpacity: boundedDouble(
                environment["DOCK_LIQUID_GLASS_BACKGROUND_OPACITY"],
                range: 0 ... 1,
                fallback: 0
            ),
            windowBlurRadius: boundedDouble(
                environment["DOCK_LIQUID_GLASS_WINDOW_BLUR"],
                range: 0 ... 64,
                fallback: 6
            ),
            contentInset: boundedDouble(
                environment["DOCK_LIQUID_GLASS_CONTENT_INSET"],
                range: 0 ... 12,
                fallback: 4
            ),
            backgroundPlateOpacity: 0.001
        )
    }

    private static func boundedDouble(
        _ raw: String?,
        range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard let raw = trimmed(raw),
              let value = Double(raw),
              value.isFinite,
              range.contains(value) else { return fallback }
        return value
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

enum DockLiquidGlassPanelGeometry {
    /// 背景窗口的 frame = 内容窗口去掉 20pt 阴影透明边后的**可视底板矩形**。
    ///
    /// 内容窗口保留透明边（阴影住在那里，且一批投放区/命中判定都按「窗口 frame 减
    /// shadowPadding」换算），背景窗口则要严丝合缝贴着底板，否则 WindowServer 的模糊会
    /// 从玻璃边缘漏出来。
    static func backgroundFrame(
        for contentPanelFrame: CGRect,
        shadowPadding: CGFloat
    ) -> CGRect {
        guard shadowPadding > 0 else { return contentPanelFrame }
        return contentPanelFrame.insetBy(dx: shadowPadding, dy: shadowPadding)
    }
}

enum DockLiquidGlassPanelRole: Equatable {
    case background
    case content
}

enum DockLiquidGlassPanelLifecyclePlan {
    static func ordering(
        isCompositeActive: Bool,
        shouldShow: Bool
    ) -> [DockLiquidGlassPanelRole] {
        guard isCompositeActive else { return [.content] }
        return shouldShow ? [.background, .content] : [.content, .background]
    }
}

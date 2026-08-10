import AppKit
import os
import SwiftUI

enum WindowTitleTextMetrics {
    /// 条内标题的最大宽度（中档基线）。**渲染和截断判定必须共用同一个值**——
    /// 以前 `ChipView` 那边写死 140、这边也写死 140，两处随缩放各走各的就会出现
    /// 「视觉上截断了但不弹 tooltip」（或反之）。任务条缩放后一律走 `maximumWidth(for:)`。
    static let maximumWidth: CGFloat = 140
    static let truncationTolerance: CGFloat = 2

    static func maximumWidth(for scale: CGFloat) -> CGFloat { maximumWidth * scale }

    static func font(scale: CGFloat) -> NSFont {
        let size = max(10, 12 * scale)
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    static func intrinsicWidth(of title: String, scale: CGFloat) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: font(scale: scale)]).width
    }

    static func isTruncated(
        intrinsicWidth: CGFloat,
        maximumWidth: CGFloat = maximumWidth,
        tolerance: CGFloat = truncationTolerance
    ) -> Bool {
        ceil(intrinsicWidth) > maximumWidth + tolerance
    }

    static func needsTooltip(for title: String, scale: CGFloat) -> Bool {
        guard !title.isEmpty else { return false }
        return isTruncated(
            intrinsicWidth: intrinsicWidth(of: title, scale: scale),
            maximumWidth: maximumWidth(for: scale)
        )
    }
}

/// 带标题窗口卡「药丸」的布局常量。**渲染与推导必须共用它**——tooltip 的锚点契约是 pill rect
/// （见 `PanelGeometry.windowTitleTooltipTargetFrame`），而屏幕坐标探针为了躲开按压缩放改量的是
/// 整张卡的矩形，pill rect 只能由这些常量推出来。两处各写一份迟早对不上，理由同 `WindowTitleTextMetrics`。
enum ChipPillMetrics {
    /// 卡片总高（= 面板内容高，`DockSize` 中档基线）。
    static let chipHeight: CGFloat = 52
    /// 药丸的布局盒高度：**恒定**，悬停时药丸自身缩到 `hoveredHeight`，盒子不变
    /// —— 这正是"悬停不再重排纵向布局"的支点。
    static let boxHeight: CGFloat = 34
    static let hoveredHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 10
    /// 图标的**布局**槽位（视觉尺寸 22→18 只在槽位内缩，槽位不变，宽度因此不随悬停变化）。
    static let iconSlot: CGFloat = 22
    static let iconSpacing: CGFloat = 6

    /// 药丸盒顶边到卡片顶边的距离：两个 `Spacer` 平分 `chipHeight - boxHeight`。
    static let boxTopInset: CGFloat = (chipHeight - boxHeight) / 2

    static func height(hovered: Bool, scale: CGFloat) -> CGFloat {
        (hovered ? hoveredHeight : boxHeight) * scale
    }

    /// 药丸宽度 = 左右内边距 + 图标槽 + 间距 + 标题实际渲染宽度（受 `WindowTitleTextMetrics` 上限约束）。
    static func width(title: String, scale: CGFloat) -> CGFloat {
        let titleWidth = min(
            WindowTitleTextMetrics.intrinsicWidth(of: title, scale: scale),
            WindowTitleTextMetrics.maximumWidth(for: scale)
        )
        return (2 * horizontalPadding + iconSlot + iconSpacing) * scale + ceil(titleWidth)
    }

    /// 由稳定的卡片屏幕矩形推出药丸屏幕矩形（macOS 屏幕坐标 y 向上）。
    /// 药丸在卡内水平居中，所以 `midX` 直接沿用卡片的；竖向全部来自上面的常量。
    static func pillRect(
        inCard card: CGRect,
        title: String,
        hovered: Bool,
        scale: CGFloat
    ) -> CGRect {
        let pillHeight = height(hovered: hovered, scale: scale)
        let shift = hovered ? ChipSubtitleMetrics.pillHoverShift(for: scale) : 0
        // offset(y:) 在 SwiftUI 里 y 向下为正；屏幕坐标 y 向上，所以顶边要减去它。
        let topY = card.maxY - boxTopInset * scale - shift
        let pillWidth = width(title: title, scale: scale)
        return CGRect(
            x: card.midX - pillWidth / 2,
            y: topY - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
    }
}

/// 悬停时药丸下方那行应用名的几何。它在新结构里**布局高度恒为 0**（只贡献宽度），
/// 位置靠 `offset` 定，所以两个位移量必须算准——否则悬停观感就变了。
///
/// 推导：对旧布局解方程。**注意旧的 `VStack(spacing: 2)` 里那个 2 是不缩放的**
///（周围全都乘了 `scale`，只有它没有），所以两个位移量都不是 `k * scale` 的形状——
/// 在中档 `s = 1` 上巧合相等，小/大/特大档就会错开。`s` = scale，`Hs` = 副标题行高（已随字号缩放）。
///
/// 旧静息 `[Spacer, 2, pill(34s), 2, Spacer]`，总高 `52s`
///   → Spacer 各 `9s - 2`，药丸顶边 `= 9s`（两个不缩放的 2 正好抵消）
/// 旧悬停 `[Spacer, 2, pill(28s), 2, sub(Hs), 2, Spacer]`
///   → Spacer 各 `(24s - 6 - Hs)/2`，药丸顶边 `= 12s - 1 - Hs/2`，副标题顶边 = 药丸顶边 `+ 28s + 2`
///
/// 新结构：药丸盒顶边恒为 `9s`（`spacing: 0`，两个 Spacer 平分 `52s - 34s`），
/// 副标题零高基线在 `43s`、文字以基线为中心。于是：
/// - `pillHoverShift = (12s - 1 - Hs/2) - 9s = 3s - 1 - Hs/2`
/// - `subtitleShift  = (40s + 1) - 43s = 1 - 3s` —— **与 Hs 无关**
///
/// 两条都由 `ChipSubtitleMetricsTests` 直接对着上面这组旧布局公式锁住。
enum ChipSubtitleMetrics {
    /// 副标题宽度上限（中档基线），与 `ChipView` 渲染共用。
    static let maximumWidth: CGFloat = 160

    static func maximumWidth(for scale: CGFloat) -> CGFloat { maximumWidth * scale }

    /// 副标题零高基线的位移。与行高无关，但**与 scale 不成正比**（见上面的推导）。
    static func subtitleShift(for scale: CGFloat) -> CGFloat { 1 - 3 * scale }

    /// 必须与 `ChipView` 里 `Text(appName)` 用的字体完全一致。
    static func font(scale: CGFloat) -> NSFont {
        let size = max(8, 9 * scale)
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    /// 副标题单行行高 `Hs`：旧布局里它是 VStack 的一个真实行，药丸的悬停上移量由它决定。
    static func rowHeight(for scale: CGFloat) -> CGFloat {
        ceil(NSLayoutManager().defaultLineHeight(for: font(scale: scale)))
    }

    static func pillHoverShift(for scale: CGFloat) -> CGFloat {
        3 * scale - 1 - rowHeight(for: scale) / 2
    }

    /// 悬停时副标题占的布局宽度。**必须是确定数值**：`.frame(width: nil)` 不可插值，
    /// SwiftUI 会直接跳到 intrinsic 布局，横向 reflow 的动画就没了。
    static func width(of name: String, scale: CGFloat) -> CGFloat {
        guard !name.isEmpty else { return 0 }
        let intrinsic = (name as NSString).size(withAttributes: [.font: font(scale: scale)]).width
        return min(ceil(intrinsic), maximumWidth(for: scale))
    }
}

struct ChipHoverVisual: Equatable {
    let progress: CGFloat
    let bareIconSize: CGFloat
    let pillHeight: CGFloat
    let pillIconSize: CGFloat
    let pillShift: CGFloat
    let subtitleSlotWidth: CGFloat
    let subtitleOpacity: Double
    let emphasisProgress: Double

    static func resolve(progress rawProgress: CGFloat, scale: CGFloat, subtitleNaturalWidth: CGFloat) -> ChipHoverVisual {
        let progress = min(max(rawProgress, 0), 1)
        func interpolate(_ rest: CGFloat, _ hovered: CGFloat) -> CGFloat {
            rest + (hovered - rest) * progress
        }
        return ChipHoverVisual(
            progress: progress,
            bareIconSize: interpolate(36 * scale, 24 * scale),
            pillHeight: interpolate(ChipPillMetrics.boxHeight * scale, ChipPillMetrics.hoveredHeight * scale),
            pillIconSize: interpolate(ChipPillMetrics.iconSlot * scale, 18 * scale),
            pillShift: ChipSubtitleMetrics.pillHoverShift(for: scale) * progress,
            subtitleSlotWidth: subtitleNaturalWidth * progress,
            subtitleOpacity: Double(progress),
            emphasisProgress: Double(progress)
        )
    }
}

struct ChipHoverProgress<Content: View>: View, Animatable {
    var progress: CGFloat
    let content: (CGFloat) -> Content

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    init(progress: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.progress = progress
        self.content = content
    }

    var body: some View {
        content(min(max(progress, 0), 1))
    }
}

enum ChipAnimationTrace {
    private static let enabled = ProcessInfo.processInfo.environment["DOCK_CHIP_ANIM_TRACE"] == "1"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.caye.macosdockcc.v2",
        category: "ChipAnimation"
    )

    static func record(chipID: String, kind: String, visual: ChipHoverVisual) {
        guard enabled else { return }
        logger.debug(
            "chip=\(chipID, privacy: .public) kind=\(kind, privacy: .public) progress=\(visual.progress) pillHeight=\(visual.pillHeight) pillShift=\(visual.pillShift) subtitleOpacity=\(visual.subtitleOpacity)"
        )
    }
}

struct WindowTitleTooltipRequest: Equatable {
    let chipID: String
    let title: String
    let anchorVisibleRect: CGRect
}

enum WindowTitleTooltipEvent: Equatable {
    case update(WindowTitleTooltipRequest)
    case exit(chipID: String)
}

struct WindowTitleTooltipView: View {
    let title: String

    /// 浅 / 深色两套视觉数值（见 `DockThemeTokens`）。
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DockThemeTokens { .resolve(colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(theme.tooltipText.color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // 材质本身跟随系统外观，这层是再压一道染色：深色加黑压暗，浅色反过来加白提亮。
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.tooltipTint.color)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.tooltipRim.color, lineWidth: 0.5)
            )
            .dockShadow(theme.tooltipShadow)
            .padding(PanelGeometry.windowTitleTooltipShadowPadding)
    }
}

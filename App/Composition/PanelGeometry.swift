import CoreGraphics

/// Taskbar height as the user dragged it: whole points, clamped to `minimum...maximum`.
///
/// Every scaled size multiplies `scale`, which is normalised to `native` (the real Dock's
/// bar height) so that a bar at 54pt renders byte-for-byte the signed-off native pixels.
/// Heights are rounded to whole points before anything derives from them; a fractional
/// height would put corner radius, icons and the hairline divider on half pixels.
struct DockPanelHeight: Equatable {
    /// 32…120 mirrors the reach of the Dock's own Size slider (tile 16…128 around a default of
    /// 48) rather than a comfort band around `native`. Both ends are reached only through the
    /// settings slider or the grip; nothing seeds them. Below ~38pt the unscaled 9pt ▲▼ grip
    /// glyph reaches past the chip *frame* by under 1pt but stays short of the icon artwork
    /// (`ChipPillMetrics.bareIconVisibleSlot` keeps 3.75pt × scale of transparent margin).
    static let minimum: CGFloat = 32
    static let maximum: CGFloat = 120

    /// 54 = the native macOS Dock bar height (@2x screenshot: 108px). Icons (40pt,
    /// `ChipHoverVisual.bareIconSize`) and `ChipPillMetrics.chipHeight` are tuned to it;
    /// changing one without the others breaks the 0.741 icon/bar ratio.
    static let native = DockPanelHeight(validated: 54)
    static let `default` = native

    let points: CGFloat

    /// Non-finite → default; otherwise rounded to whole points and clamped.
    init(clamping raw: CGFloat) {
        guard raw.isFinite else {
            self = .default
            return
        }
        self.init(validated: min(max(raw.rounded(), Self.minimum), Self.maximum))
    }

    private init(validated points: CGFloat) {
        self.points = points
    }

    /// Multiplier for every tier-scaled size. Exactly `1.0` at `native`.
    var scale: CGFloat { points / Self.native.points }

    /// Legacy four-tier raw values (`com.tungsten.edge.dockSize`), read once for migration.
    static func migratingLegacyTier(rawValue: String) -> DockPanelHeight? {
        switch rawValue {
        case "small": return DockPanelHeight(clamping: 46)
        case "medium": return DockPanelHeight(clamping: 54)
        case "large": return DockPanelHeight(clamping: 62)
        case "extraLarge": return DockPanelHeight(clamping: 70)
        default: return nil
        }
    }

    /// The single source of panel geometry: AppKit (`PanelCoordinator`) and SwiftUI both
    /// read it, never their own copy.
    var metrics: PanelLayoutMetrics {
        PanelLayoutMetrics(
            panelHeight: points,
            // Shadow padding never scales: the shadow tokens are frozen.
            shadowPadding: PanelLayoutMetrics.shadowPadding,
            // Written as an expression, not a literal: the relation used to live only in a
            // comment and is exactly what a height change forgets.
            windowHeight: points + 2 * PanelLayoutMetrics.shadowPadding,
            bottomGap: 8,
            outerMargin: 12,
            capsuleWidth: points,
            capsuleGap: 8,
            minimumDockWidth: 120 * scale,
            minimumDrawerExtent: 120
        )
    }
}

struct PanelLayoutMetrics: Equatable {
    var panelHeight: CGFloat
    var shadowPadding: CGFloat
    var windowHeight: CGFloat
    var bottomGap: CGFloat
    var outerMargin: CGFloat
    var capsuleWidth: CGFloat
    var capsuleGap: CGFloat
    var minimumDockWidth: CGFloat
    var minimumDrawerExtent: CGFloat

    /// Fixed; never scales with the bar height (see `DockPanelHeight.metrics`).
    static let shadowPadding: CGFloat = 20

    /// Native-height baseline for default parameters and tests; real values come from
    /// `DockPanelHeight.metrics`.
    static let tungstenEdge = DockPanelHeight.native.metrics
}

/// The drawer capsule's four-up preview (2 × 2). Values are at the native height and scale with the
/// bar: `columns × icon + spacing + 2 × padding` must fit `capsuleWidth` at every height
/// (`PanelGeometryTests.testCapsuleGridContentFitsEveryHeight`).
enum DrawerCapsulePreviewMetrics {
    static let columns = 2
    static let limit = columns * columns
    static let iconSize: CGFloat = 17
    static let gridSpacing: CGFloat = 4
    static let gridPadding: CGFloat = 7

    static var contentWidth: CGFloat {
        CGFloat(columns) * iconSize + CGFloat(columns - 1) * gridSpacing + 2 * gridPadding
    }
}

struct PanelScreenGeometry: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat

    /// The drawer's top cap still follows top system UI. On displays without a notch,
    /// this usually tracks visibleFrame.maxY and may change when the menu bar auto-hides.
    /// On notched displays, the safe-area cap can take over once the menu bar is hidden,
    /// so the same known edge can be smaller there than on external displays.
    var topUsableY: CGFloat {
        min(visibleFrame.maxY, frame.maxY - safeAreaTop)
    }
}

enum PanelGeometry {
    static let windowTitleTooltipScreenMargin: CGFloat = 8
    /// 阴影留白**不随档位缩放**：气泡的阴影 token 本身是固定的，跟着缩会动到定稿的观感。
    /// 视图侧和这里必须用同一个值（视图 `.padding(它)`，这里再减回去）。
    static let windowTitleTooltipShadowPadding: CGFloat = 8

    /// The bar and the drawer capsule to its right are centered as one group, the way the native
    /// Dock centers its whole row. Centering the bar alone leaves the set (gap + capsule) / 2 right
    /// of center; at the width cap the group keeps `outerMargin` on both sides.
    static func dockTargetFrame(
        contentWidth: CGFloat,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let trailing = metrics.capsuleGap + metrics.capsuleWidth
        let maxWidth = screen.frame.width - 2 * metrics.outerMargin - trailing
        let panelWidth = max(min(contentWidth, maxWidth), metrics.minimumDockWidth)
        let x = screen.frame.minX + (screen.frame.width - (panelWidth + trailing)) / 2
        return CGRect(
            x: x - metrics.shadowPadding,
            y: screen.frame.minY + metrics.bottomGap - metrics.shadowPadding,
            width: panelWidth + metrics.shadowPadding * 2,
            height: metrics.windowHeight
        )
    }

    static func capsuleTargetFrame(
        forDock dockFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let rawX = dockFrame.maxX - metrics.shadowPadding + metrics.capsuleGap
        let rawY = dockFrame.minY + metrics.shadowPadding + (metrics.panelHeight - metrics.capsuleWidth) / 2
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - metrics.capsuleWidth)
        let clampedY = min(max(rawY, screen.frame.minY), screen.frame.maxY - metrics.capsuleWidth)
        return CGRect(
            x: clampedX - metrics.shadowPadding,
            y: clampedY - metrics.shadowPadding,
            width: metrics.capsuleWidth + metrics.shadowPadding * 2,
            height: metrics.capsuleWidth + metrics.shadowPadding * 2
        )
    }

    /// 弹窗锚定+钳位的**单一真相**：给定"期望中心 X / 期望底边 Y / 尺寸"，算出贴屏钳位后的 origin。
    /// folderPopupTargetFrame（首帧/重定位）和切换动画的每帧插值都走它，避免钳位规则在两处各写一份漂移。
    static func folderPopupClampedOrigin(
        desiredCenterX: CGFloat,
        desiredBottomY: CGFloat,
        size: CGSize,
        on screen: PanelScreenGeometry
    ) -> CGPoint {
        let bottom = max(desiredBottomY, screen.frame.minY)
        let x = min(max(desiredCenterX - size.width / 2, screen.frame.minX), screen.frame.maxX - size.width)
        return CGPoint(x: x, y: bottom)
    }

    /// 固定文件夹弹窗：锚点（chip 可视矩形，屏幕坐标）上方 8pt，水平居中钳进屏，
    /// 只向上生长、topUsableY 封顶——同 drawer 的底锚策略。`size` 为含阴影的整面板尺寸。
    static func folderPopupTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let origin = folderPopupClampedOrigin(
            desiredCenterX: anchorVisibleRect.midX, desiredBottomY: anchorVisibleRect.maxY + 8,
            size: size, on: screen)
        let height = min(size.height, max(metrics.minimumDrawerExtent, screen.topUsableY - origin.y))
        return CGRect(x: origin.x, y: origin.y, width: size.width, height: height)
    }

    static func maxFolderPopupContentHeight(
        anchorVisibleRect: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGFloat {
        let bottom = anchorVisibleRect.maxY + 8
        return max(metrics.minimumDrawerExtent, (screen.topUsableY - bottom) - 2 * metrics.shadowPadding)
    }

    /// Window-title tooltip panel frame. The panel includes transparent padding for its SwiftUI
    /// shadow, while the visible bubble stays 8pt above the pill and 8pt inside the screen edges.
    /// `tipGap` = 气泡**尖端**到锚点顶边的距离，随档位缩放，由调用方从
    /// `WindowTitleTooltipStyle.tipGap` 传进来——系数只在样式那一处算，这里不再算第二遍。
    static func windowTitleTooltipTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        tipGap: CGFloat,
        on screen: PanelScreenGeometry
    ) -> CGRect {
        let inset = windowTitleTooltipShadowPadding
        let visibleWidth = max(0, size.width - 2 * inset)
        let visibleHeight = max(0, size.height - 2 * inset)
        let minVisibleX = screen.frame.minX + windowTitleTooltipScreenMargin
        let maxVisibleX = screen.frame.maxX - windowTitleTooltipScreenMargin - visibleWidth
        let desiredVisibleX = anchorVisibleRect.midX - visibleWidth / 2
        let visibleX = min(max(desiredVisibleX, minVisibleX), maxVisibleX)
        let desiredVisibleY = anchorVisibleRect.maxY + tipGap
        let maxVisibleY = screen.topUsableY - visibleHeight
        let visibleY = min(desiredVisibleY, maxVisibleY)

        return CGRect(
            x: visibleX - inset,
            y: visibleY - inset,
            width: size.width,
            height: size.height
        )
    }

    static func drawerTargetFrame(
        forCapsule capsuleFrame: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let bottom = max(capsuleFrame.maxY - metrics.shadowPadding + 8, screen.frame.minY)
        let height = min(size.height, max(metrics.minimumDrawerExtent, screen.topUsableY - bottom))
        let rawX = capsuleFrame.maxX - size.width
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - size.width)
        return CGRect(x: clampedX, y: bottom, width: size.width, height: height)
    }

    static func maxDrawerContentHeight(
        forCapsule capsuleFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGFloat {
        let drawerBottomY = capsuleFrame.maxY - metrics.shadowPadding + 8
        return max(metrics.minimumDrawerExtent, (screen.topUsableY - drawerBottomY) - 2 * metrics.shadowPadding)
    }
}

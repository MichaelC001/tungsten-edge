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
    /// **必须等于 `DockSize.medium.panelHeight`**：卡撑满条高、上下不留空隙，
    /// 任务条空白区右键的判定就建立在「没有垂直空隙」上。2026-08-16 随中档 52→54 一起改。
    static let chipHeight: CGFloat = 54
    /// 药丸的布局盒高度：**恒定**，悬停时药丸自身缩到 `hoveredHeight`，盒子不变
    /// —— 这正是"悬停不再重排纵向布局"的支点。
    static let boxHeight: CGFloat = 34
    static let hoveredHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 10
    /// 带标题的窗口卡在药丸两侧再留的空当。
    ///
    /// 图标卡靠图标资源自带的透明边距撑出可见的缝，药丸是实心背景、自己撑不出来，
    /// 所以 `Style.chipSpacing` 从 8 缩到 2（对齐原生图标间距）之后，两张标题卡就贴到
    /// 一起了（owner 2026-08-16「多窗口的标签间隙做大一些」）。
    /// 两张标题卡之间的可见缝 = `2 * titledCardInset + Style.chipSpacing` = 10pt，
    /// 与图标之间的可见缝（实测 10pt）一致。
    ///
    /// 加在**整张卡**上而不是药丸里：药丸尺寸是签收过的观感，而且 `pillRect(inCard:)`
    /// 按「药丸在卡内水平居中」反推 tooltip 锚点，对称内边距不影响那条契约。
    static let titledCardInset: CGFloat = 4
    /// 图标的**布局**槽位（视觉尺寸 22→18 只在槽位内缩，槽位不变，宽度因此不随悬停变化）。
    static let iconSlot: CGFloat = 22
    static let iconSpacing: CGFloat = 6

    /// 无标题（纯图标）卡的图标尺寸：静息 = 原生 Dock 的 tilesize，悬停收缩给应用名让位。
    ///
    /// **`bareIconSlot` 同时是布局槽位的高度**——`ChipView` 里那个 `ZStack` 是 `.top` 对齐的，
    /// 槽位比静息图标小就会让图标整块往下溢出（2026-08-16：图标从 36 改成 40 而槽位仍写死 36，
    /// 实测图标在卡里下移 4pt，上下留白变成 12.5 / 8.0）。两者必须同一个常量。
    static let bareIconSlot: CGFloat = 40
    static let bareIconHovered: CGFloat = 26
    /// 纯图标卡的卡宽。**中心间距 = `cardWidth + Style.chipSpacing`，两者要一起看。**
    /// 2026-08-16 实测原生 Dock 的图标中心间距是 42pt（40 的 tile + 2pt 缝），
    /// 钨极原来是 52pt（44 + 8），稀疏了一倍；改成 40 + 2 对齐。
    /// 卡宽等于图标尺寸，所以图标横向没有额外余量——原生也是这样，
    /// 可见的缝来自图标资源自带的透明边距。
    static let cardWidth: CGFloat = 40
    /// 悬停时应用名相对槽位顶边的位移：收缩后的图标底边再往下 2pt。
    static var bareSubtitleOffset: CGFloat { bareIconHovered + 2 }

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
/// 新结构：药丸盒顶边恒为 `boxTopInset * s`（`spacing: 0`，两个 Spacer 平分
/// `chipHeight*s - 34s`），副标题零高基线在药丸盒底边、文字以基线为中心。
/// 下面用卡高 52 的历史取值（`boxTopInset = 9`、基线 `43s`）推导：
/// - `pillHoverShift = (12s - 1 - Hs/2) - 9s = 3s - 1 - Hs/2`
/// - `subtitleShift  = (40s + 1) - 43s = 1 - 3s` —— **与 Hs 无关**
///
/// 卡高在 2026-08-16 由 52 改成 54（对齐原生 Dock），两个位移量**都不用改**：
/// 基线和旧布局的目标位置一起平移了 `1s`，差值不变。`ChipSubtitleMetricsTests`
/// 里的公式已改成从 `chipHeight` / `boxTopInset` 推导，不再写死 52 / 9 / 43。
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
            // 静止 40 = 原生 Dock 的 tilesize（2026-08-16 owner 拍板对齐原生，同时条高 52→54）。
            // 悬停 26 保持原来约 2/3 的收缩比（原 36→24）：副标题是零高 overlay，不占布局，
            // 收缩纯粹是给下方冒出的应用名腾视觉空间。
            bareIconSize: interpolate(
                ChipPillMetrics.bareIconSlot * scale,
                ChipPillMetrics.bareIconHovered * scale
            ),
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
    private static let runtime = Runtime()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.caye.macosdockcc.v2",
        category: "ChipAnimation"
    )

    static func record(
        chipID: String,
        kind: String,
        visual: ChipHoverVisual,
        isTapPressed: Bool,
        showsHover: Bool
    ) {
        guard enabled else { return }
        runtime.record(
            chipID: chipID,
            kind: kind,
            uptime: ProcessInfo.processInfo.systemUptime,
            visual: visual,
            state: ChipAnimationTraceState(isTapPressed: isTapPressed, showsHover: showsHover)
        )
    }

    static func event(
        chipID: String,
        kind: String,
        event: String,
        isTapPressed: Bool,
        showsHover: Bool
    ) {
        guard enabled else { return }
        runtime.event(
            chipID: chipID,
            kind: kind,
            uptime: ProcessInfo.processInfo.systemUptime,
            event: event,
            state: ChipAnimationTraceState(isTapPressed: isTapPressed, showsHover: showsHover)
        )
    }

    private final class Runtime: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.caye.macosdockcc.v2.chip-animation-trace")
        private let fileManager = FileManager.default
        private var buffer = ChipAnimationTraceBuffer(capacity: 4_096)
        private var sessionByChip: [String: UUID] = [:]
        private var lastVisualByChip: [String: ChipHoverVisual] = [:]
        private var quiescenceGeneration: UInt64 = 0

        func record(
            chipID: String,
            kind: String,
            uptime: TimeInterval,
            visual: ChipHoverVisual,
            state: ChipAnimationTraceState
        ) {
            queue.async { [self] in
                let key = "\(kind)\u{0}\(chipID)"
                let isNewSession = sessionByChip[key] == nil
                let sessionID = sessionByChip[key] ?? UUID()
                sessionByChip[key] = sessionID
                lastVisualByChip[key] = visual
                appendSample(
                    sessionID: sessionID,
                    chipID: chipID,
                    kind: kind,
                    uptime: uptime,
                    visual: visual,
                    state: state,
                    event: isNewSession ? "sessionStart" : nil
                )
                scheduleExportAfterQuiescence()
            }
        }

        func event(
            chipID: String,
            kind: String,
            uptime: TimeInterval,
            event: String,
            state: ChipAnimationTraceState
        ) {
            queue.async { [self] in
                let key = "\(kind)\u{0}\(chipID)"
                let sessionID = sessionByChip[key] ?? UUID()
                sessionByChip[key] = sessionID
                appendSample(
                    sessionID: sessionID,
                    chipID: chipID,
                    kind: kind,
                    uptime: uptime,
                    visual: lastVisualByChip[key],
                    state: state,
                    event: event
                )
                scheduleExportAfterQuiescence()
            }
        }

        private func appendSample(
            sessionID: UUID,
            chipID: String,
            kind: String,
            uptime: TimeInterval,
            visual: ChipHoverVisual?,
            state: ChipAnimationTraceState,
            event: String?
        ) {
            buffer.append(ChipAnimationTraceSample(
                sessionID: sessionID,
                chipID: chipID,
                kind: kind,
                uptime: uptime,
                hoverProgress: visual.map { Double($0.progress) },
                bareIconSize: visual.map { Double($0.bareIconSize) },
                pillHeight: visual.map { Double($0.pillHeight) },
                pillIconSize: visual.map { Double($0.pillIconSize) },
                pillShift: visual.map { Double($0.pillShift) },
                subtitleSlotWidth: visual.map { Double($0.subtitleSlotWidth) },
                subtitleOpacity: visual?.subtitleOpacity,
                emphasisProgress: visual?.emphasisProgress,
                isTapPressed: state.isTapPressed,
                showsHover: state.showsHover,
                event: event
            ))
        }

        private func scheduleExportAfterQuiescence() {
            quiescenceGeneration &+= 1
            let generation = quiescenceGeneration
            queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.quiescenceGeneration == generation else { return }
                self.exportBufferedSamples()
            }
        }

        private func exportBufferedSamples() {
            let samples = buffer.drain()
            guard !samples.isEmpty else { return }
            sessionByChip.removeAll(keepingCapacity: true)
            lastVisualByChip.removeAll(keepingCapacity: true)

            do {
                let url = try traceFileURL()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                var payload = Data()
                for sample in samples {
                    payload.append(try encoder.encode(sample))
                    payload.append(0x0A)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
                let sessionCount = Set(samples.map(\.sessionID)).count
                ChipAnimationTrace.logger.info(
                    "exported samples=\(samples.count) sessions=\(sessionCount) path=\(url.path, privacy: .public)"
                )
            } catch {
                ChipAnimationTrace.logger.error("trace export failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        private func traceFileURL() throws -> URL {
            let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
            let directory = library
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("com.caye.macosdockcc.v2", isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = directory.appendingPathComponent("chip-animation-trace.jsonl")
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(
                    atPath: url.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            return url
        }
    }
}

struct ChipAnimationTraceState: Equatable {
    let isTapPressed: Bool
    let showsHover: Bool
}

enum ChipAnimationTraceEvent {
    static func hover(_ hovering: Bool) -> String { hovering ? "hoverEntered" : "hoverExited" }
    static func tap(_ pressed: Bool) -> String { pressed ? "tapPressed" : "tapReleased" }
}

struct ChipAnimationTraceSample: Codable, Equatable {
    let sessionID: UUID
    let chipID: String
    let kind: String
    let uptime: TimeInterval
    let hoverProgress: Double?
    let bareIconSize: Double?
    let pillHeight: Double?
    let pillIconSize: Double?
    let pillShift: Double?
    let subtitleSlotWidth: Double?
    let subtitleOpacity: Double?
    let emphasisProgress: Double?
    let isTapPressed: Bool
    let showsHover: Bool
    let event: String?
}

struct ChipAnimationTraceBuffer {
    let capacity: Int
    private(set) var samples: [ChipAnimationTraceSample] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ sample: ChipAnimationTraceSample) {
        if samples.count == capacity {
            samples.removeFirst()
        }
        samples.append(sample)
    }

    mutating func drain() -> [ChipAnimationTraceSample] {
        defer { samples.removeAll(keepingCapacity: true) }
        return samples
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

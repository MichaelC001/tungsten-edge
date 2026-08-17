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
    /// 药丸的布局盒高度。**悬停时不再变**（2026-08-16：应用名挪进了图标上方的气泡，
    /// 药丸不用再让位）。
    static let boxHeight: CGFloat = 34
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
    /// 图标槽位里**实际画出来的方块**有多大。
    ///
    /// 苹果的图标资源自带约 18% 的透明边距（2026-08-16 实测：40pt 的槽位里可见方块 32.5pt），
    /// 条上可见的图标间缝就是这么来的。所以**任何我们自己画的、不带透明边距的图形**
    /// （中转格那枚）必须按这个尺寸画，否则它会比邻居明显大一圈——owner 报过的「太突兀」
    /// 有一半是大小，不只是颜色。
    static let bareIconVisibleSlot: CGFloat = 32.5
    /// 纯图标卡的卡宽。**中心间距 = `cardWidth + Style.chipSpacing`，两者要一起看。**
    /// 2026-08-16 实测原生 Dock 的图标中心间距是 42pt（40 的 tile + 2pt 缝），
    /// 钨极原来是 52pt（44 + 8），稀疏了一倍；改成 40 + 2 对齐。
    /// 卡宽等于图标尺寸，所以图标横向没有额外余量——原生也是这样，
    /// 可见的缝来自图标资源自带的透明边距。
    static let cardWidth: CGFloat = 40

    /// 药丸盒顶边到卡片顶边的距离：两个 `Spacer` 平分 `chipHeight - boxHeight`。
    static let boxTopInset: CGFloat = (chipHeight - boxHeight) / 2

    static func height(scale: CGFloat) -> CGFloat { boxHeight * scale }

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
        scale: CGFloat
    ) -> CGRect {
        let pillHeight = height(scale: scale)
        let topY = card.maxY - boxTopInset * scale
        let pillWidth = width(title: title, scale: scale)
        return CGRect(
            x: card.midX - pillWidth / 2,
            y: topY - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
    }
}


/// 悬停时 chip 的视觉。**几何恒定不变，只有「我在这上面」的提亮随进度走。**
///
/// 2026-08-16 之前这里还插值三样东西：裸图标 40→26、药丸盒 34→28、药丸内图标 22→18，
/// 外加一行从零宽长出来的应用名。那套收缩**唯一的理由是给图标下方那行名字腾地方**——
/// 名字改成原生 Dock 那种「图标正上方的气泡」之后（owner 2026-08-16），理由就没了：
/// 原生悬停时图标不缩不动。硬留着只会让整条在鼠标扫过时抖。
///
/// 一并作废的还有 `ChipSubtitleMetrics` 那套对着旧 `VStack(spacing: 2)` 布局解方程得来的
/// 位移公式（`pillHoverShift` / `subtitleShift`）——**别再把它们请回来**。
struct ChipHoverVisual: Equatable {
    let progress: CGFloat
    let bareIconSize: CGFloat
    let pillHeight: CGFloat
    let pillIconSize: CGFloat
    /// 药丸底与描边的强调程度。这是**唯一**还随悬停变化的量。
    let emphasisProgress: Double

    static func resolve(progress rawProgress: CGFloat, scale: CGFloat) -> ChipHoverVisual {
        let progress = min(max(rawProgress, 0), 1)
        return ChipHoverVisual(
            progress: progress,
            bareIconSize: ChipPillMetrics.bareIconSlot * scale,
            pillHeight: ChipPillMetrics.boxHeight * scale,
            pillIconSize: ChipPillMetrics.iconSlot * scale,
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

/// 原生 macOS 26 Dock 那颗应用名气泡的实测尺寸。
///
/// 2026-08-17 从 owner 的原生截图上逐像素量的（@2x，黑底，"ChatGPT"）——**别再凭印象改**，
/// 要改先重新截图重新量：
///
/// | | 实测 |
/// |---|---|
/// | 形状 | **胶囊**（不是圆角矩形）。高 26pt → 圆角 13pt；两侧半圆之间是直边 |
/// | 高 | 26pt |
/// | 左右留白 | 各 14pt（量到字的墨迹；扣掉字形自带的边距后写 13） |
/// | 字 | 宽 57pt / 墨迹高 10.5pt → SF 14pt regular（13pt 只有 54.5 宽，明显窄） |
/// | 尖角 | **向下**，基部宽 23pt、高 6.5pt、居中；基部外扩、中段直边、**尖端是圆头** |
/// | 尖端离条顶 | 6.5pt |
/// | 填充 | 纯黑底上读到灰 173 |
///
/// 尖角侧影在两张不同宽度的原生截图里**逐像素一致**（半宽 16.5/14/12.5/10.5/9.5/8.5/7.5/
/// 6.5/5.5/4/3 @2x），所以它是固定尺寸的零件，不随气泡宽度变。中段斜率约 1.17（半宽/深度），
/// 外推到 0 应在 7.1pt 处，实际 6.5pt 就收——**差的那截就是圆头**（owner 说的「更圆润」）。
enum WindowTitleTooltipStyle {
    static let height: CGFloat = 26
    static let cornerRadius: CGFloat = height / 2
    static let horizontalPadding: CGFloat = 13
    static let fontSize: CGFloat = 14
    static let tailWidth: CGFloat = 23
    static let tailHeight: CGFloat = 6.5
    /// 直边段的上端：基部外扩到这里收住。
    static let tailShoulderDepth: CGFloat = 1.6
    static let tailShoulderHalfWidth: CGFloat = 6.6
    /// 圆头起点：从这里开始是那顶圆帽。
    static let tailTipDepth: CGFloat = 5.6
    static let tailTipHalfWidth: CGFloat = 1.9
    /// 尖端到锚点顶边的距离。
    static let tipGap: CGFloat = 6.5
    static let maximumWidth: CGFloat = 360
}

/// 胶囊 + 向下水滴尖角。尖角画在**形状里**而不是叠一个三角形：
/// 叠加的话两块的描边会在接缝处交叉出一条横线，原生那颗是一整块连续的轮廓。
struct WindowTitleTooltipShape: InsettableShape {
    /// `strokeBorder` 用：把描边**整条画在形状里面**。
    ///
    /// 原来用 `stroke`，它把线骑在轮廓上——0.5pt 的线有一半落到形状外，被抗锯齿吃掉一半，
    /// 实测描边只有 197 而原生是 209（同背景折算）。描边是「利落」的唯一来源，不能打折。
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in outerRect: CGRect) -> Path {
        let rect = outerRect.insetBy(dx: insetAmount, dy: insetAmount)
        let tail = WindowTitleTooltipStyle.tailHeight
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: max(0, rect.height - tail))
        let radius = min(WindowTitleTooltipStyle.cornerRadius, body.height / 2)
        let halfTail = min(WindowTitleTooltipStyle.tailWidth, body.width) / 2
        let centerX = body.midX

        var path = Path()
        // 胶囊主体：右半圆 → 上边 → 左半圆 → 下边（走到尖角基部左侧）。
        path.move(to: CGPoint(x: body.maxX - radius, y: body.maxY))
        path.addArc(center: CGPoint(x: body.maxX - radius, y: body.midY),
                    radius: radius, startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addArc(center: CGPoint(x: body.minX + radius, y: body.midY),
                    radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        // 尖角三段（原生实测）：基部外扩的凹肩 → 中段直边 → 圆头。
        // **不是一个尖点**：外推直边应在 7.1pt 处收口，实际 6.5pt 就到底，差的那截是圆帽。
        let base = body.maxY
        let shoulderY = base + WindowTitleTooltipStyle.tailShoulderDepth
        let shoulderX = WindowTitleTooltipStyle.tailShoulderHalfWidth
        let tipY = base + WindowTitleTooltipStyle.tailTipDepth
        let tipX = WindowTitleTooltipStyle.tailTipHalfWidth
        // 二次曲线在 t=0.5 处到达 (起点 + 2×控制点 + 终点)/4，所以控制点的 y 这样反解出峰值 = base + tail。
        let capControlY = 2 * (base + tail) - tipY

        path.addLine(to: CGPoint(x: centerX - halfTail, y: base))
        path.addQuadCurve(to: CGPoint(x: centerX - shoulderX, y: shoulderY),
                          control: CGPoint(x: centerX - halfTail * 0.83, y: base + tail * 0.05))
        path.addLine(to: CGPoint(x: centerX - tipX, y: tipY))
        path.addQuadCurve(to: CGPoint(x: centerX + tipX, y: tipY),
                          control: CGPoint(x: centerX, y: capControlY))
        path.addLine(to: CGPoint(x: centerX + shoulderX, y: shoulderY))
        path.addQuadCurve(to: CGPoint(x: centerX + halfTail, y: base),
                          control: CGPoint(x: centerX + halfTail * 0.83, y: base + tail * 0.05))
        path.closeSubpath()
        return path
    }
}

struct WindowTitleTooltipView: View {
    let title: String

    private let theme = DockThemeTokens.standard

    var body: some View {
        let shape = WindowTitleTooltipShape()
        return Text(title)
            .font(.system(size: WindowTitleTooltipStyle.fontSize, weight: .regular))
            .foregroundStyle(theme.tooltipText.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: WindowTitleTooltipStyle.maximumWidth)
            .padding(.horizontal, WindowTitleTooltipStyle.horizontalPadding)
            // 文字盒撑满主体高度并居中；尖角靠额外的下内边距占位，文字不会被它带偏。
            .frame(height: WindowTitleTooltipStyle.height)
            .padding(.bottom, WindowTitleTooltipStyle.tailHeight)
            // **底下不垫 `.ultraThinMaterial`。** 实测它在这里只透过约 54% 的背景、而且不加白，
            // 垫着只会把整颗压暗：白底上我们读到 174，原生该是 249。降底板不透明度也救不回来
            // ——算下来要板色 384 才够，超出 255。代价是没有背景模糊（原生有），
            // 但只透三成，糊不糊看不太出来；真要补，得用 macOS 26 的玻璃效果，不是这层材质。
            .background(shape.fill(theme.tooltipPlate.color.opacity(theme.tooltipPlateOpacity)))
            .overlay(shape.strokeBorder(theme.tooltipRim.color, lineWidth: 0.5))
            .dockShadow(theme.tooltipShadow)
            .padding(PanelGeometry.windowTitleTooltipShadowPadding)
    }
}

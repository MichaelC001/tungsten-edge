import CoreGraphics
import Foundation
import QuartzCore

/// 任务条交互的手感诊断。默认关闭，`DOCK_HOVER_TRACE=1` 打开。
/// （文件名沿用 `hover-trace.jsonl`：它最初只量悬停，2026-08-17 扩到点击 / 最小化那条路径，
/// 2026-08-18 再扩到拖拽。所有手感诊断共用这一个开关和一个文件——多开一套 I/O 没有意义。）
///
/// 悬停部分回答两个问题：
/// 1. **鼠标匀速划过一排图标时，每个 chip 都收到悬停回调了吗？** 少了就是事件被合并掉了，
///    问题在主线程占用，不在气泡本身。
/// 2. **收到之后，把气泡摆到位花了多久？** 长就是渲染/窗口调用慢，那才是气泡自己的问题。
///
/// 顺带记主线程的**卡顿**：一个 8ms 的重复计时器，量每次实际触发比预定晚了多少。
/// 这是「事件被合并」的直接证据——AGENTS《Menus, Panels, And Screens》里那条 100ms 粘滞
/// 当年就是靠"主线程闲着但事件到得晚"才辨出来的，光看 CPU 占用看不出来。
///
/// 落盘在 `~/Library/Logs/com.caye.macosdockcc.v2/hover-trace.jsonl`。
enum HoverTrace {
    static let isEnabled = ProcessInfo.processInfo.environment["DOCK_HOVER_TRACE"] == "1"

    /// chip 报告悬停进入 / 离开。
    static func hover(chipID: String, entered: Bool) {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"hover\",\"chip\":\(quote(chipID)),\"in\":\(entered)}")
    }

    /// 协调器真正把气泡摆好用了多久（含 SwiftUI 重排 + setFrame）。
    static func present(chipID: String, cold: Bool, elapsed: CFTimeInterval) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"present\",\"chip\":\(quote(chipID))," +
            "\"cold\":\(cold),\"ms\":\(round(elapsed * 10000) / 10)}"
        )
    }

    /// 整条那块跟踪区每收到一次指针位置就记一行，附带算出来的归属。
    ///
    /// **这是「悬停到底跟不跟得上」唯一的现场证据。** 2026-08-17 改成整条一块跟踪区时，
    /// 第一版靠 `NSTrackingArea` 的 `.mouseMoved`，实测每 35 次指针移动只有个位数报上来
    /// （我们这些面板永远不是 key 窗口）。没有这一行就只能靠猜。
    static func pointer(x: CGFloat, chip: String?) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"pointer\",\"x\":\(round(x * 10) / 10)," +
            "\"chip\":\(chip.map(quote) ?? "null")}"
        )
    }

    /// 主线程卡顿：预定 8ms 触发，实际晚了 `lateMs`。只记超过 12ms 的，免得自己刷屏。
    /// 60Hz 下一帧 16.7ms，所以 >16.7 基本等于至少掉一帧。
    static func mainLoopStall(lateMs: Double) {
        guard isEnabled, lateMs >= 12 else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"stall\",\"lateMs\":\(round(lateMs * 10) / 10)}")
    }

    // MARK: - 点击 / 最小化那条路径（owner 2026-08-17 报「点击和最小化之后的动作会卡」）

    /// 任务条 body 求值一次。**用来回答「一次点击让整条重算了几次」**——
    /// `DockStripView` 订阅的是整个 `AppRuntime`，任何一个 `@Published` 变化都会打翻整条。
    static func stripBody(items: Int) {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"stripBody\",\"items\":\(items)}")
    }

    /// 一次 `relayout`：同步量整条宽度花了多久、量出多少、和上次比变没变、是否带动画。
    ///
    /// **`changed:false` 且 `animated:true` 就是纯浪费**——宽度没变还要跑一遍窗口尺寸动画，
    /// 而那动画的每一帧都要重画玻璃底板和描边。这是本轮头号嫌疑。
    static func relayout(measureMs: CFTimeInterval, width: CGFloat, changed: Bool, animated: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"relayout\",\"measureMs\":\(round(measureMs * 10000) / 10)," +
            "\"width\":\(round(width * 10) / 10),\"changed\":\(changed),\"animated\":\(animated)}"
        )
    }

    /// 面板 frame 全等 → 整组动画被跳过。**这条是上面那条浪费真的被堵住的证据**，
    /// 光看 `relayout` 次数看不出来（短路发生在下游的 `setFrames` 里）。
    static func framesUnchanged() {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"framesSkipped\"}")
    }

    /// 用户动作的时间窗标记。没有它，日志里一堆卡顿不知道该算在谁头上。
    static func action(_ kind: String, phase: String) {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"action\",\"what\":\(quote(kind)),\"phase\":\(quote(phase))}")
    }

    // MARK: - 拖拽（owner 2026-08-18 报「从抽屉拖进任务条不容易挤开别的图标 / 会出现两个影子」）

    /// 抽屉图标拖向任务条时，**每一次光标位置更新**都记一行判定现场。
    ///
    /// 这条存在的理由和 `pointer` 一样：转正判定是一串 `guard`，任何一条不过就静默返回，
    /// 从外面看全是「没反应」。没有这一行只能靠猜是几何、是模式、还是落点。
    /// `enter` / `clearlyOut` 是那个迟滞框的两个布尔，`mode` 是 `DrawerDragOutMode`。
    static func drawerToStrip(x: CGFloat, y: CGFloat,
                              strip: CGRect,
                              enter: Bool, clearlyOut: Bool,
                              mode: String, converted: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"d2s\",\"x\":\(r1(x)),\"y\":\(r1(y))," +
            "\"sx\":\(r1(strip.minX)),\"sy\":\(r1(strip.minY))," +
            "\"sw\":\(r1(strip.width)),\"sh\":\(r1(strip.height))," +
            "\"enter\":\(enter),\"out\":\(clearlyOut),\"mode\":\(quote(mode)),\"conv\":\(converted)}"
        )
    }

    /// 转正 / 回滚那一刻的落点暂存。**`target` 为 null = 整块落到 live 区末尾**——
    /// 而转正期间任务条宽度是冻结的，落末尾往往被裁在可视区外，看起来就是「什么都没发生」。
    static func drawerToStripStage(bundleID: String, target: String?, after: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"d2sStage\",\"bid\":\(quote(bundleID))," +
            "\"target\":\(target.map(quote) ?? "null"),\"after\":\(after)}"
        )
    }

    /// 转正态下「载体画哪张卡」与「条上隐藏哪张卡」各是谁。
    /// 两者**必须同时有值**，否则条上那张卡不透明地画着、手里又拎着一个 = 两个影子。
    static func carrierRepresentative(rep: String?, hidden: String?) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"carrierRep\"," +
            "\"rep\":\(rep.map(quote) ?? "null"),\"hidden\":\(hidden.map(quote) ?? "null")}"
        )
    }

    /// 转正后的整块连续重排：这一次有没有找到落点目标。`target` 为 null = 光标没压在任何一张
    /// live 卡上（在条外、在消息区/文件夹区、或在卡与卡之间），于是**整块原地不动**。
    static func stripBlockReorder(target: String?, after: Bool, why: String) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"blockReorder\",\"target\":\(target.map(quote) ?? "null")," +
            "\"after\":\(after),\"why\":\(quote(why))}"
        )
    }

    /// 起拖那一帧各步花了多久（owner 2026-08-18 报「选中图标拖动的第一帧有卡顿」）。
    /// `carrierCreated` = 这次是不是现建的载体面板——建面板要连带起一棵 SwiftUI 宿主树，
    /// 只有整个会话的第一次拖动会付这笔钱，靠它才分得清「每次都卡」还是「只有第一次卡」。
    static func dragStart(totalMs: Double, carrierMs: Double, carrierCreated: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"dragStart\",\"ms\":\(round(totalMs * 10) / 10)," +
            "\"carrierMs\":\(round(carrierMs * 10) / 10),\"created\":\(carrierCreated)}"
        )
    }

    /// 起拖之后的三个时刻，用来定位「图标凭空消失」那段空档到底卡在哪一步。
    /// `what` 取值：`beginDrag` / `slotHidden`（条上那张卡真的藏了）/ `carrierDrawn`（副本真的画了第一帧）。
    /// **空档 = slotHidden 早于 carrierDrawn**，两者之差就是屏幕上什么都没有的时长。
    static func dragHandoff(_ what: String, msSinceBegin: Double) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"handoff\",\"what\":\(quote(what))," +
            "\"ms\":\(round(msSinceBegin * 10) / 10)}"
        )
    }

    /// 载体宿主视图摆到哪了：想要的原点、设完立刻读回的、下一轮再读回的、以及它是不是还在自动布局手里。
    /// **`deferred` 和 `wanted` 对不上就说明有人把它挪走了**（自动布局在下一次 layout 覆盖 frame 是头号嫌疑）。
    static func carrierPlacement(wanted: CGPoint, immediate: CGPoint, deferred: CGPoint,
                                 size: CGSize, autolayout: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"place\",\"wx\":\(r1(wanted.x)),\"wy\":\(r1(wanted.y))," +
            "\"ix\":\(r1(immediate.x)),\"iy\":\(r1(immediate.y))," +
            "\"dx\":\(r1(deferred.x)),\"dy\":\(r1(deferred.y))," +
            "\"w\":\(r1(size.width)),\"h\":\(r1(size.height)),\"al\":\(autolayout)}"
        )
    }

    /// **不变量自检**：条上那格已经空了，副本却不在屏幕上 —— 这一刻用户看到的就是「图标凭空消失」。
    /// 把「偶尔会出现」变成一条可以事后统计的记录，不用再靠截图猜。
    static func carrierGap(reason: String, alpha: Double, hostX: CGFloat, hostY: CGFloat) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"GAP\",\"why\":\(quote(reason))," +
            "\"alpha\":\(round(alpha * 100) / 100),\"hx\":\(r1(hostX)),\"hy\":\(r1(hostY))}"
        )
    }

    /// 副作用路径 `reconcileLiveOrder` 这一轮拿到的是不是**新鲜**的 projection。
    ///
    /// 这条是 2026-08-18 那个坑的直接证据，值得常驻：老式 `onChange(of:perform:)` 触发时
    /// 跑的是上一帧装进去的闭包，projection 落后一代——渲染已经有这张卡了、`sync` 手里还没有，
    /// 于是抽屉转正的落点暂存一次都没被消费。`carried=true` 而 `has=false` 就是它复发了。
    static func orderSync(count: Int, carriedID: String?, hasCarried: Bool) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"orderSync\",\"n\":\(count)," +
            "\"carried\":\(carriedID.map(quote) ?? "null"),\"has\":\(hasCarried)}"
        )
    }

    /// 顺序层真正落子后的可见序（只在拖拽诊断打开时记）。判「缝到底开在哪一格」的最终依据。
    static func liveOrder(_ ids: [String]) {
        guard isEnabled else { return }
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"liveOrder\",\"ids\":[\(ids.map(quote).joined(separator: ","))]}"
        )
    }

    /// 松手后的归位飞行：起点、终点、有没有拿到锚点。
    /// `to` 为 null = 没有落点锚点，走瞬时收尾（老行为）。
    static func landing(from: CGPoint, to: CGPoint?, source: String) {
        guard isEnabled else { return }
        let target = to.map { "[\(r1($0.x)),\(r1($0.y))]" } ?? "null"
        Writer.shared.append(
            "{\"t\":\(stamp()),\"kind\":\"landing\",\"from\":[\(r1(from.x)),\(r1(from.y))]," +
            "\"to\":\(target),\"src\":\(quote(source))}"
        )
    }

    private static func r1(_ value: CGFloat) -> Double { (Double(value) * 10).rounded() / 10 }

    private static func stamp() -> Double { round(CACurrentMediaTime() * 10000) / 10 }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private final class Writer {
        static let shared = Writer()
        private let queue = DispatchQueue(label: "com.caye.macosdockcc.v2.hovertrace")

        func append(_ line: String) {
            queue.async { [self] in
                guard let fileURL, let data = (line + "\n").data(using: .utf8) else { return }
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }

        private lazy var fileURL: URL? = {
            let fm = FileManager.default
            guard let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
            let dir = base.appendingPathComponent("Logs/com.caye.macosdockcc.v2", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("hover-trace.jsonl")
        }()
    }
}

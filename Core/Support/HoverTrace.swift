import CoreGraphics
import Foundation
import QuartzCore

/// 任务条交互的手感诊断。默认关闭，`DOCK_HOVER_TRACE=1` 打开。
/// （文件名沿用 `hover-trace.jsonl`：它最初只量悬停，2026-08-17 扩到点击 / 最小化那条路径。）
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

    static func dismiss(reason: String) {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"dismiss\",\"why\":\(quote(reason))}")
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

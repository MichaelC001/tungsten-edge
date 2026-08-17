import Foundation
import QuartzCore

/// 悬停名气泡的跟手度诊断。默认关闭，`DOCK_HOVER_TRACE=1` 打开。
///
/// 回答的问题只有两个，别扩：
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

    static func dismiss(reason: String) {
        guard isEnabled else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"dismiss\",\"why\":\(quote(reason))}")
    }

    /// 主线程卡顿：预定 8ms 触发，实际晚了 `lateMs`。只记超过 12ms 的，免得自己刷屏。
    static func mainLoopStall(lateMs: Double) {
        guard isEnabled, lateMs >= 12 else { return }
        Writer.shared.append("{\"t\":\(stamp()),\"kind\":\"stall\",\"lateMs\":\(round(lateMs * 10) / 10)}")
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

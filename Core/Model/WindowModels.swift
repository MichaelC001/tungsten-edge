import Foundation
import CoreGraphics

struct WindowRecord: Hashable, Sendable {
    let id: WindowID
    let appID: AppID
    let pid: Int32
    let bundleIdentifier: String?
    var title: String
    var bounds: CGRect?
    var status: WindowStatus
    var cgWindowID: CGWindowID?
    var isOnDesktop: Bool
    /// 稳定分组身份（标签组根治）。同一物理窗口的所有原生标签座位共享同一个 token，一旦分配就
    /// **不随当前激活标签的 CGWindowID 变化**；普通单窗口是自成一组的 token。任务条据此合并、
    /// 并以它作为卡片的稳定 id（切标签 / 后台标签来去都不换身份证 → 卡片不跳不裂）。
    /// 默认空串 = 退化为按 `id` 各自独立（兼容未赋值路径）。
    var groupID: String

    init(
        id: WindowID,
        appID: AppID,
        pid: Int32,
        bundleIdentifier: String?,
        title: String,
        bounds: CGRect?,
        status: WindowStatus,
        cgWindowID: CGWindowID? = nil,
        isOnDesktop: Bool = false,
        groupID: String = ""
    ) {
        self.id = id
        self.appID = appID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.bounds = bounds
        self.status = status
        self.cgWindowID = cgWindowID
        self.isOnDesktop = isOnDesktop
        self.groupID = groupID.isEmpty ? id.rawValue : groupID
    }
}

enum WindowStatus: String, Hashable, Codable, Sendable {
    case active
    case inactive
    case minimized
    case hidden
    case closedPending
    case disappeared
}

/// 乐观状态 overlay（交互打磨 2026-06-13）：点击发出显隐类动作（activate / minimize /
/// hide）的瞬间，先本地假定窗口已变成目标状态，UI 与下一次 toggle 规划都优先读它，
/// 不等快照 round-trip —— 这就是「可打断 / 连点衔接」的根。真实快照兑现预测或超时
/// 后清除（静默回弹）。close / quit 不写乐观态（窗口要消失，失败回弹会闪）。
///
/// 只预测 status，不预测前台轴（2026-07-05）：前台轴有即时准确的系统读数（新建
/// NSRunningApplication 实例的 isActive，SkyLight 切换后立即翻面），预测它只会出错——
/// 曾有残留满 4s 的 isAppFrontmost=true 把「别的 App 在前时点卡片」误规划成 minimize。
struct OptimisticWindowState: Hashable, Sendable {
    let status: WindowStatus
    let createdAt: Date
}

extension OptimisticWindowState {
    /// 兄弟顶替即清（2026-08-22）：预测 .active 尚未兑现、而同 App 另一窗口已被快照证实
    /// .active —— 焦点已被兄弟拿走，这份预测再挂满 4 秒只会把下一次点击误规划成 minimize。
    /// macOS 26 曾把 SkyLight make-key 静默废掉，误最小化正是靠这类残留发作；留这层防御，
    /// 未来焦点通道再静默失效时症状降级为「多余的 activate」而不是「误 minimize」。
    /// 只清 .active 预测：minimize / hidden 的兑现语义（含 disappeared）与兄弟状态无关。
    static func supersededByActiveSibling(
        windowID: String,
        predicted: WindowStatus,
        snapshot: DockSnapshot
    ) -> Bool {
        guard predicted == .active else { return false }
        guard let record = snapshot.windows[WindowID(rawValue: windowID)] else { return false }
        return snapshot.windows.values.contains {
            $0.pid == record.pid && $0.id != record.id && $0.status == .active
        }
    }

    /// 兄弟激活在飞（2026-08-25）：同 App 另一窗口持有尚未被快照兑现的乐观 .active——
    /// 焦点正在交接途中，此刻本窗口的「active」读数（快照或乐观残留）都不可信：来回快点
    /// 两个可见窗口时，点后台窗曾被误收起（Release 实测，click-latency 里 6 条
    /// 「快照 inactive 却规划成 minimize」）。用于 toggle 规划的收起判定降级
    /// （见 LifecycleActionPlanner），哲学同上一条：宁可多余 activate，绝不错误 minimize。
    static func siblingActivationInFlight(
        windowID: String,
        optimisticStates: [String: OptimisticWindowState],
        snapshot: DockSnapshot
    ) -> Bool {
        guard let record = snapshot.windows[WindowID(rawValue: windowID)] else { return false }
        return optimisticStates.contains { key, state in
            guard key != windowID, state.status == .active else { return false }
            guard let sibling = snapshot.windows[WindowID(rawValue: key)] else { return false }
            return sibling.pid == record.pid && sibling.status != .active
        }
    }
}

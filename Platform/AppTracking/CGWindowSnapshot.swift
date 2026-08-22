import CoreGraphics
import Foundation

struct AppTrackerCGWindowSnapshot: Equatable {
    let allWindowIDs: Set<CGWindowID>
    let onScreenWindowIDs: Set<CGWindowID>
    /// 按属主 pid 分组的 layer-0 窗口 id（影子标签池用：CG(pid) − AX 暴露集 = order-out 后台标签）。
    let windowIDsByPID: [pid_t: Set<CGWindowID>]
    /// AX inventory 没有透明度属性；按同轮 CG window id 补齐，供 admission 的 alpha=0 过滤使用。
    let alphaByWindowID: [CGWindowID: Double]
    /// CG 查询本身失败（返回 nil）。与「真的没有 layer-0 窗口」是两回事：任何拿本快照当
    /// 「没变化」判据的门控（周期跳读、补扫门控）见此标志必须放弃跳过、走全量路径。
    /// 既有消费方不读它，失败时的下游行为与从前逐位一致。
    let captureFailed: Bool

    init(
        allWindowIDs: Set<CGWindowID>,
        onScreenWindowIDs: Set<CGWindowID>,
        windowIDsByPID: [pid_t: Set<CGWindowID>],
        alphaByWindowID: [CGWindowID: Double],
        captureFailed: Bool = false
    ) {
        self.allWindowIDs = allWindowIDs
        self.onScreenWindowIDs = onScreenWindowIDs
        self.windowIDsByPID = windowIDsByPID
        self.alphaByWindowID = alphaByWindowID
        self.captureFailed = captureFailed
    }

    static var failed: AppTrackerCGWindowSnapshot {
        AppTrackerCGWindowSnapshot(
            allWindowIDs: [],
            onScreenWindowIDs: [],
            windowIDsByPID: [:],
            alphaByWindowID: [:],
            captureFailed: true
        )
    }

    static func capture() -> AppTrackerCGWindowSnapshot {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return .failed
        }
        return parse(windowInfo)
    }

    static func captureOnScreenWindowIDs() -> Set<CGWindowID> {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return layerZeroWindowIDs(in: windowInfo)
    }

    static func parse(_ windowInfo: [[String: Any]]) -> AppTrackerCGWindowSnapshot {
        var allWindowIDs: Set<CGWindowID> = []
        var onScreenWindowIDs: Set<CGWindowID> = []
        var windowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        var alphaByWindowID: [CGWindowID: Double] = [:]

        for info in windowInfo {
            guard let windowID = layerZeroWindowID(in: info) else { continue }
            allWindowIDs.insert(windowID)
            if info[kCGWindowIsOnscreen as String] as? Bool == true {
                onScreenWindowIDs.insert(windowID)
            }
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int {
                windowIDsByPID[pid_t(ownerPID), default: []].insert(windowID)
            }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue {
                alphaByWindowID[windowID] = alpha
            }
        }

        return AppTrackerCGWindowSnapshot(
            allWindowIDs: allWindowIDs,
            onScreenWindowIDs: onScreenWindowIDs,
            windowIDsByPID: windowIDsByPID,
            alphaByWindowID: alphaByWindowID
        )
    }

    private static func layerZeroWindowIDs(in windowInfo: [[String: Any]]) -> Set<CGWindowID> {
        Set(windowInfo.compactMap(layerZeroWindowID(in:)))
    }

    private static func layerZeroWindowID(in info: [String: Any]) -> CGWindowID? {
        guard let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0,
              let number = info[kCGWindowNumber as String] as? Int else {
            return nil
        }
        return CGWindowID(number)
    }
}

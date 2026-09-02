import AppKit
import Combine

/// 在场屏幕表（display UUID + Quartz 帧 + 主屏）的唯一来源。任务条投影层（多屏 ④ 的按屏过滤）
/// 和窗口清单（`AppTracker` 的归属键）读同一张表，两边对「哪块屏」永远一致。
/// 只在 `didChangeScreenParametersNotification` 时重算——`DisplayIdentity` 有系统调用，不在
/// SwiftUI body 里现算。
@MainActor
final class DisplayTopologyStore: ObservableObject {
    @Published private(set) var table: WindowDisplayAttribution.Table

    private var screenParametersObserver: NSObjectProtocol?

    init() {
        table = DisplayIdentity.attributionTable()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refresh() {
        let next = DisplayIdentity.attributionTable()
        if next != table { table = next }
    }
}

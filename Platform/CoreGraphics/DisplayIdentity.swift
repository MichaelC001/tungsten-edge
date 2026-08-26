import AppKit

/// NSScreen → display UUID（`CGDisplayCreateUUIDFromDisplayID`，基于 EDID，
/// 拔插 / 换口 / 休眠唤醒后稳定）。任务条「固定到某屏」的持久化身份用它，
/// **绝不按 `NSScreen.screens` 数组序号记屏**。
/// 逻辑与 `FullscreenIntentMonitor.swift` 里 `ManagedSpaceLayoutReader.displayUUIDString(for:)`
/// 同源（那个文件的细节被规则冻结，刻意不共享实现）。
enum DisplayIdentity {
    @MainActor
    static func uuidString(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String?
    }

    /// 在场的屏 →（display UUID, 去重后的展示名）。读不出 UUID 的屏不进列表（固定不了它）。
    /// **有系统 I/O（`localizedName` 会读 IODisplay），别在菜单弹出路径上现算**——
    /// 调用方应在屏幕参数变化时缓存一份（`StatusMenuController` 即如此）。
    @MainActor
    static func connectedScreenOptions() -> [(uuid: String, title: String)] {
        let identified: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
            guard let uuid = uuidString(for: screen) else { return nil }
            return (uuid, screen.localizedName)
        }
        let titles = TaskbarScreenResolution.displayTitles(names: identified.map(\.name))
        return zip(identified, titles).map { ($0.uuid, $1) }
    }
}

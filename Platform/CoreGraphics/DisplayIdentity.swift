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
}

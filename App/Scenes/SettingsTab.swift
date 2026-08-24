import Combine
import Foundation

/// 设置窗口的六个标签页（2026-08-24 分页、同日反馈拎出为独立标签，见 `Docs/27`）。标题复用原分区标题的
/// 本地化 key；图标全部 macOS 11 起可用（对照 CoreGlyphs name_availability 核过）。
/// 纯 Foundation/Combine——测试 target 也编译它，别引 AppKit。
enum SettingsTab: String, CaseIterable {
    case general
    case taskbar
    case advanced
    case license
    case feedback
    case about

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .taskbar: return String(localized: "Taskbar")
        case .advanced: return String(localized: "Advanced")
        case .license: return String(localized: "License")
        case .feedback: return String(localized: "Feedback")
        case .about: return String(localized: "About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .taskbar: return "dock.rectangle"
        case .advanced: return "wrench.and.screwdriver"
        case .license: return "key"
        case .feedback: return "paperplane"
        case .about: return "info.circle"
        }
    }
}

/// controller → SwiftUI 的选中页桥。controller 持有唯一一份 = 会话内记住所选标签；
/// **不落 UserDefaults**（与「设置窗口不跨重启记位置」同一条规矩）。
/// 量高探针必须共享这同一个实例，否则量的是别的页。
@MainActor
final class SettingsTabState: ObservableObject {
    @Published var selected: SettingsTab = .general
}

import Foundation

/// 界面语言三档（2026-08-24 定，反转 2026-08-17「不额外做界面语言开关」，见 `Docs/27`）。
///
/// 机制：写**应用自己域**的 `AppleLanguages`——这正是 macOS 13+「系统设置 → 通用 →
/// 语言与地区 → 应用程序」逐 App 语言写的同一个键，两条路互通，顺带把逐 App 语言
/// 能力带到了 macOS 12。「跟随系统」= 删除该键。**下次启动生效**：SwiftUI + 手搭
/// AppKit 菜单 + 多个常驻 NSHostingView 的热切换要重建所有面板，不值得；业界惯例也是重启。
///
/// 三档而非二选一：不带「跟随系统」会迫使现有用户选一次、并改变默认行为。
enum AppLanguageOption: String, CaseIterable, Equatable {
    case followSystem
    case zhHans
    case english

    /// 从**本 app 域**读出的 `AppleLanguages` 判断当前档。
    ///
    /// ⚠️ 调用方不能用 `UserDefaults.standard.array(forKey:)` 取值——它会继承全局域
    ///（系统语言列表永远非空），分不清「跟随系统」和「显式设置」。要用
    /// `CFPreferencesCopyAppValue` / `persistentDomain(forName:)` 取**本域**值传进来。
    /// 域里是别的语言（用户在系统设置里给本 app 选了第三种）→ 归「跟随系统」显示：
    /// 界面只有中英两种，第三种语言实际回落英文，picker 不该谎称其中某档。
    static func current(appDomainValue: [String]?) -> AppLanguageOption {
        guard let first = appDomainValue?.first?.lowercased(), !first.isEmpty else {
            return .followSystem
        }
        if first.hasPrefix("zh") { return .zhHans }
        if first.hasPrefix("en") { return .english }
        return .followSystem
    }

    /// 该写进 `AppleLanguages` 的值；nil = 删除键（跟随系统）。
    var appleLanguagesValue: [String]? {
        switch self {
        case .followSystem: return nil
        case .zhHans: return ["zh-Hans"]
        case .english: return ["en"]
        }
    }

    /// 展示名。两个具体语言**用它自己的语言写死**（语言选单的通用惯例，两种界面语言下
    /// 都显示同样的字），只有「跟随系统」跟随界面语言翻译。
    var displayName: String {
        switch self {
        case .followSystem: return String(localized: "System")
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

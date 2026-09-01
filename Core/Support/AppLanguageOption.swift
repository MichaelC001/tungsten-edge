import Foundation

/// 界面语言两档（2026-09-01 由三档收成两档，删掉「跟随系统」，owner 拍板；三档那版见 `Docs/27`）。
///
/// 机制：写**应用自己域**的 `AppleLanguages`——这正是 macOS 13+「系统设置 → 通用 →
/// 语言与地区 → 应用程序」逐 App 语言写的同一个键，两条路互通，顺带把逐 App 语言
/// 能力带到了 macOS 12。**下次启动生效**：SwiftUI + 手搭 AppKit 菜单 + 多个常驻
/// NSHostingView 的热切换要重建所有面板，不值得；业界惯例也是重启。
///
/// ⚠️ **删掉的是选项，不是机制。** 「跟随系统」= 该键不存在，而这仍然是**没选过语言的人
/// 的真实状态**：他们的界面照旧由 macOS 按系统语言决定，一个字都没变。选单只是把
/// 「此刻实际生效的是哪一档」显示出来，读取路径**绝不回写**——一旦有人在读的时候顺手
/// `set`，就等于替所有从没选过的用户把语言钉死，英文系统装上的人会被钉在推断值上。
/// 只有用户主动点选才写键。
enum AppLanguageOption: String, CaseIterable, Equatable {
    case zhHans
    case english

    /// 当前该显示哪一档。
    ///
    /// - `appDomainValue`: 从**本 app 域**读出的 `AppleLanguages`。⚠️ 调用方不能用
    ///   `UserDefaults.standard.array(forKey:)` 取值——它会继承全局域（系统语言列表永远非空），
    ///   分不清「没设过」和「显式设置」。要用 `CFPreferencesCopyAppValue` /
    ///   `persistentDomain(forName:)` 取本域值传进来。
    /// - `effectiveLocalization`: 此刻**真正加载的那份 `.lproj`**（`Bundle.main.preferredLocalizations.first`）。
    ///   没设过、或域里是第三种语言（用户在系统设置里给本 app 选了日语这类）时按它回答：
    ///   界面只有中英两种，第三种语言实际回落英文，选单就该显示 English，不谎称。
    ///
    /// **兜底方向是英文，不是中文**：只有 `zh` 开头才判简体中文。写反了会让英文系统的用户
    /// 在选单里看到「简体中文」——单测钉的就是这一条。
    static func current(appDomainValue: [String]?, effectiveLocalization: String) -> AppLanguageOption {
        if let explicit = appDomainValue?.first?.lowercased(), !explicit.isEmpty {
            if explicit.hasPrefix("zh") { return .zhHans }
            if explicit.hasPrefix("en") { return .english }
        }
        return effectiveLocalization.lowercased().hasPrefix("zh") ? .zhHans : .english
    }

    /// 该写进 `AppleLanguages` 的值。两档都是显式值——「删键」那条路随「跟随系统」一起没了。
    var appleLanguagesValue: [String] {
        switch self {
        case .zhHans: return ["zh-Hans"]
        case .english: return ["en"]
        }
    }

    /// 展示名。**两档都用它自己的语言写死**（语言选单的通用惯例），所以这里没有任何
    /// 需要本地化的字符串——中英两种界面下显示的是同样两行字。
    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

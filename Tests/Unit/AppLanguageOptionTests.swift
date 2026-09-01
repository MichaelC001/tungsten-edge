import XCTest

final class AppLanguageOptionTests: XCTestCase {
    /// 没设过语言（键不存在）时按**实际生效的界面语言**显示，而不是空白或某个写死的档。
    func testUnsetDomainFollowsTheEffectiveLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "zh-Hans"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: [], effectiveLocalization: "en"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: [""], effectiveLocalization: "en-US"), .english)
    }

    /// ⚠️ 兜底方向必须是英文。写反了，英文系统的用户打开设置会看到「简体中文」被选中。
    /// 第三种语言的系统（法语这类）界面实际回落英文，选单也该显示 English。
    func testFallbackIsEnglishForEveryNonChineseLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "fr"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: ""), .english)
    }

    func testRecognizesChineseAndEnglishVariants() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-Hans", "en"], effectiveLocalization: "en"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-CN"], effectiveLocalization: "en"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en"], effectiveLocalization: "zh-Hans"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en-US"], effectiveLocalization: "zh-Hans"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["EN"], effectiveLocalization: "zh-Hans"), .english, "大小写不敏感")
    }

    /// 用户在系统设置里给本 app 选了第三种语言：域里是 `fr`，界面实际回落英文，
    /// 选单按实际生效的那份 `.lproj` 显示 English——不谎称用户选过中文。
    func testThirdLanguageInDomainFallsBackToTheEffectiveLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["fr"], effectiveLocalization: "en"), .english)
    }

    func testAppleLanguagesValueRoundTripsThroughCurrent() {
        for option in AppLanguageOption.allCases {
            XCTAssertEqual(
                AppLanguageOption.current(
                    appDomainValue: option.appleLanguagesValue,
                    // 故意传相反的界面语言：显式值必须压过推断值。
                    effectiveLocalization: option == .zhHans ? "en" : "zh-Hans"
                ),
                option,
                "写下去再读回来必须是同一档：\(option)"
            )
        }
    }

    func testDisplayNamesAreLanguageStable() {
        XCTAssertEqual(AppLanguageOption.zhHans.displayName, "简体中文", "语言名用它自己的语言写死")
        XCTAssertEqual(AppLanguageOption.english.displayName, "English")
    }
}

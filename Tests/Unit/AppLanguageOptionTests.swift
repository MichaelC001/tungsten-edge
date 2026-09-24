import XCTest

final class AppLanguageOptionTests: XCTestCase {
    /// 没设过语言（键不存在）时按**实际生效的界面语言**显示，而不是空白或某个写死的档。
    func testUnsetDomainFollowsTheEffectiveLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "zh-Hans"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "zh-Hant"), .zhHant)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "ja"), .japanese)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "de"), .german)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "fr"), .french)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: [], effectiveLocalization: "en"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: [""], effectiveLocalization: "en-US"), .english)
    }

    /// ⚠️ 兜底方向必须是英文。写反了，英文系统的用户打开设置会看到「简体中文」被选中。
    /// 我们没有的语言（韩语这类）界面实际回落英文，选单也该显示 English。
    func testFallbackIsEnglishForEveryUnsupportedLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "ko"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: "es-419"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil, effectiveLocalization: ""), .english)
    }

    func testRecognizesChineseAndEnglishVariants() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-Hans", "en"], effectiveLocalization: "en"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-CN"], effectiveLocalization: "en"), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh"], effectiveLocalization: "en"), .zhHans, "裸 zh 归简中")
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en"], effectiveLocalization: "zh-Hans"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en-US"], effectiveLocalization: "zh-Hans"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["EN"], effectiveLocalization: "zh-Hans"), .english, "大小写不敏感")
    }

    /// 繁中的判定必须走在「zh 开头」之前，台港澳三种写法与下划线形式都要认。
    func testTraditionalChineseVariantsAllLandOnZhHant() {
        for code in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-Hant-HK", "zh_TW", "ZH-HANT"] {
            XCTAssertEqual(AppLanguageOption.option(matching: code), .zhHant, code)
        }
        for code in ["zh-Hans", "zh-CN", "zh-SG", "zh-Hans-CN", "zh"] {
            XCTAssertEqual(AppLanguageOption.option(matching: code), .zhHans, code)
        }
    }

    func testRecognizesRegionalVariantsOfTheNewLanguages() {
        XCTAssertEqual(AppLanguageOption.option(matching: "ja-JP"), .japanese)
        XCTAssertEqual(AppLanguageOption.option(matching: "de-CH"), .german)
        XCTAssertEqual(AppLanguageOption.option(matching: "fr-CA"), .french)
        XCTAssertEqual(AppLanguageOption.option(matching: "fr_FR"), .french)
    }

    /// 用户在系统设置里给本 app 选了我们没有的语言：域里是 `ko`，界面实际回落英文，
    /// 选单按实际生效的那份 `.lproj` 显示 English——不谎称用户选过中文。
    func testUnsupportedLanguageInDomainFallsBackToTheEffectiveLocalization() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["ko"], effectiveLocalization: "en"), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["ko"], effectiveLocalization: "ja"), .japanese)
    }

    func testAppleLanguagesValueRoundTripsThroughCurrent() {
        for option in AppLanguageOption.allCases {
            XCTAssertEqual(
                AppLanguageOption.current(
                    appDomainValue: option.appleLanguagesValue,
                    // 故意传另一种界面语言：显式值必须压过推断值。
                    effectiveLocalization: option == .zhHans ? "en" : "zh-Hans"
                ),
                option,
                "写下去再读回来必须是同一档：\(option)"
            )
        }
    }

    /// 写进 `AppleLanguages` 的值同时是 `.lproj` 目录名，六个都要在构建产物里真实存在。
    func testLocalizationIdentifiersAreDistinctAndMatchTheLprojNames() {
        let identifiers = AppLanguageOption.allCases.map(\.localizationIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertEqual(Set(identifiers), ["zh-Hans", "zh-Hant", "en", "ja", "de", "fr"])
    }

    func testDisplayNamesAreLanguageStable() {
        XCTAssertEqual(AppLanguageOption.zhHans.displayName, "简体中文", "语言名用它自己的语言写死")
        XCTAssertEqual(AppLanguageOption.zhHant.displayName, "繁體中文")
        XCTAssertEqual(AppLanguageOption.english.displayName, "English")
        XCTAssertEqual(AppLanguageOption.japanese.displayName, "日本語")
        XCTAssertEqual(AppLanguageOption.german.displayName, "Deutsch")
        XCTAssertEqual(AppLanguageOption.french.displayName, "Français")
    }
}

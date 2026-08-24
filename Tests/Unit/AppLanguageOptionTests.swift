import XCTest

final class AppLanguageOptionTests: XCTestCase {
    func testMissingOrEmptyDomainValueMeansFollowSystem() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: nil), .followSystem)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: []), .followSystem)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: [""]), .followSystem)
    }

    func testRecognizesChineseAndEnglishVariants() {
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-Hans", "en"]), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["zh-CN"]), .zhHans)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en"]), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["en-US"]), .english)
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["EN"]), .english, "大小写不敏感")
    }

    func testThirdLanguagesDisplayAsFollowSystem() {
        // 用户在系统设置里给本 app 选了第三种语言：界面实际回落英文，
        // 但 picker 不该谎称「English」是用户自己选的——归「跟随系统」。
        XCTAssertEqual(AppLanguageOption.current(appDomainValue: ["fr"]), .followSystem)
    }

    func testAppleLanguagesValueRoundTripsThroughCurrent() {
        for option in AppLanguageOption.allCases {
            XCTAssertEqual(
                AppLanguageOption.current(appDomainValue: option.appleLanguagesValue),
                option,
                "写下去再读回来必须是同一档：\(option)"
            )
        }
    }

    func testDisplayNamesAreLanguageStable() {
        XCTAssertEqual(AppLanguageOption.zhHans.displayName, "简体中文", "语言名用它自己的语言写死")
        XCTAssertEqual(AppLanguageOption.english.displayName, "English")
        XCTAssertEqual(AppLanguageOption.followSystem.displayName, String(localized: "System"))
    }
}

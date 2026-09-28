import XCTest

final class FolderBadgeTextTests: XCTestCase {
    func testChineseNameGivesItsFirstCharacter() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "下载"), "下")
        XCTAssertEqual(FolderBadgeText.automatic(for: "设计 素材"), "设")
        XCTAssertEqual(FolderBadgeText.automatic(for: "スクリーンショット"), "ス")
    }

    func testSingleLatinWordGivesOneCapital() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "Downloads"), "D")
        XCTAssertEqual(FolderBadgeText.automatic(for: "projects"), "P")
        XCTAssertEqual(FolderBadgeText.automatic(for: "straße"), "S")
    }

    func testTwoLatinWordsGiveTwoInitials() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "Final Cut Projects"), "FC")
        XCTAssertEqual(FolderBadgeText.automatic(for: "my-project"), "MP")
        XCTAssertEqual(FolderBadgeText.automatic(for: "Client_files"), "CF")
    }

    func testMixedScriptKeepsOnlyTheLatinInitial() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "Final 剪辑"), "F")
    }

    func testLeadingPunctuationIsSkipped() {
        XCTAssertEqual(FolderBadgeText.automatic(for: ".config"), "C")
        XCTAssertEqual(FolderBadgeText.automatic(for: "[Work] Notes"), "WN")
        XCTAssertEqual(FolderBadgeText.automatic(for: "_Archive"), "A")
    }

    func testEmojiLeadIsKept() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "📥 Inbox"), "📥")
        XCTAssertEqual(FolderBadgeText.automatic(for: "👩‍💻 Code"), "👩‍💻")
    }

    func testDigitsAreNotMistakenForEmoji() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "2026 Taxes"), "2T")
    }

    func testDegenerateNamesStillRenderSomething() {
        XCTAssertEqual(FolderBadgeText.automatic(for: "..."), ".")
        XCTAssertEqual(FolderBadgeText.automatic(for: ""), "?")
    }

    func testCustomBadgeOverridesAndIsCapped() {
        XCTAssertEqual(FolderBadgeText.resolve(name: "Downloads", custom: "Dl"), "Dl")
        XCTAssertEqual(FolderBadgeText.resolve(name: "Downloads", custom: "  下载文件  "), "下载")
        XCTAssertEqual(FolderBadgeText.resolve(name: "Downloads", custom: "👩‍💻x"), "👩‍💻x")
    }

    func testBlankCustomFallsBackToAutomatic() {
        XCTAssertEqual(FolderBadgeText.resolve(name: "Documents", custom: "   "), "D")
        XCTAssertEqual(FolderBadgeText.resolve(name: "Documents", custom: nil), "D")
        XCTAssertNil(FolderBadgeText.sanitizedCustom("\n"))
    }

    func testStyleSwitchParsing() {
        XCTAssertEqual(FolderBadgeStyle.resolve(raw: nil, folderIndex: 0), .graphite)
        XCTAssertEqual(FolderBadgeStyle.resolve(raw: "LIGHT", folderIndex: 5), .light)
        XCTAssertEqual(FolderBadgeStyle.resolve(raw: "bogus", folderIndex: 0), .graphite)
        XCTAssertEqual((0..<4).map { FolderBadgeStyle.resolve(raw: "mix", folderIndex: $0) },
                       [.graphite, .light, .tint, .graphite])
    }
}

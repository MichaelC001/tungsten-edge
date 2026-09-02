import XCTest

final class TaskbarScreenPlacementTests: XCTestCase {
    // MARK: - resolve

    func testResolveMatchesPinnedScreen() {
        let outcome = TaskbarScreenResolution.resolve(
            pinnedUUID: "B",
            screenUUIDs: ["A", "B", "C"],
            mainIndex: 0
        )
        XCTAssertEqual(outcome, .matched(index: 1))
    }

    func testResolveFallsBackToMainWhenPinnedAbsent() {
        let outcome = TaskbarScreenResolution.resolve(
            pinnedUUID: "X",
            screenUUIDs: ["A", "B"],
            mainIndex: 1
        )
        XCTAssertEqual(outcome, .fallback(index: 1))
    }

    func testResolveFallsBackToZeroWhenMainMissing() {
        let outcome = TaskbarScreenResolution.resolve(
            pinnedUUID: "X",
            screenUUIDs: ["A", "B"],
            mainIndex: nil
        )
        XCTAssertEqual(outcome, .fallback(index: 0))
    }

    func testResolveFallsBackToZeroWhenMainIndexOutOfRange() {
        let outcome = TaskbarScreenResolution.resolve(
            pinnedUUID: "X",
            screenUUIDs: ["A"],
            mainIndex: 5
        )
        XCTAssertEqual(outcome, .fallback(index: 0))
    }

    func testResolveNilUUIDNeverMatches() {
        // 读不出 UUID 的屏（nil）不许被任何固定值匹配到。
        let outcome = TaskbarScreenResolution.resolve(
            pinnedUUID: "X",
            screenUUIDs: [nil, "A"],
            mainIndex: 0
        )
        XCTAssertEqual(outcome, .fallback(index: 0))
    }

    func testResolveEmptyScreensReturnsNil() {
        XCTAssertNil(TaskbarScreenResolution.resolve(pinnedUUID: "X", screenUUIDs: [], mainIndex: nil))
    }

    // MARK: - displayTitles

    func testDisplayTitlesUniqueNamesUntouched() {
        XCTAssertEqual(
            TaskbarScreenResolution.displayTitles(names: ["内建显示器", "LG HDR 4K"]),
            ["内建显示器", "LG HDR 4K"]
        )
    }

    func testDisplayTitlesNumbersDuplicatesFromSecondOccurrence() {
        XCTAssertEqual(
            TaskbarScreenResolution.displayTitles(names: ["LG HDR 4K", "LG HDR 4K", "内建显示器", "LG HDR 4K"]),
            ["LG HDR 4K", "LG HDR 4K (2)", "内建显示器", "LG HDR 4K (3)"]
        )
    }

    // MARK: - placement

    func testOnlyFollowMouseAllowsHoverScreenSwitching() {
        XCTAssertTrue(TaskbarScreenPlacement.followMouse.allowsHoverScreenSwitching)
        let pinned = TaskbarScreenPlacement.pinned(PinnedScreenSelection(uuid: "A", name: "LG"))
        XCTAssertFalse(pinned.allowsHoverScreenSwitching)
        XCTAssertFalse(TaskbarScreenPlacement.allScreens.allowsHoverScreenSwitching)
        XCTAssertFalse(TaskbarScreenPlacement.allScreensPerDisplay.allowsHoverScreenSwitching)
    }

    func testShowsOnEveryDisplayOnlyForAllScreensModes() {
        XCTAssertFalse(TaskbarScreenPlacement.followMouse.showsOnEveryDisplay)
        XCTAssertFalse(TaskbarScreenPlacement.pinned(PinnedScreenSelection(uuid: "A", name: "LG")).showsOnEveryDisplay)
        XCTAssertTrue(TaskbarScreenPlacement.allScreens.showsOnEveryDisplay)
        XCTAssertTrue(TaskbarScreenPlacement.allScreensPerDisplay.showsOnEveryDisplay)
        XCTAssertEqual(TaskbarScreenPlacement.allScreens.mode, .allScreens)
        XCTAssertEqual(TaskbarScreenPlacement.allScreensPerDisplay.mode, .allScreensPerDisplay)
        XCTAssertNil(TaskbarScreenPlacement.allScreens.pinnedSelection)
    }

    func testModeAndSelectionAccessors() {
        XCTAssertEqual(TaskbarScreenPlacement.followMouse.mode, .followMouse)
        XCTAssertNil(TaskbarScreenPlacement.followMouse.pinnedSelection)
        let selection = PinnedScreenSelection(uuid: "A", name: "LG")
        XCTAssertEqual(TaskbarScreenPlacement.pinned(selection).mode, .pinned)
        XCTAssertEqual(TaskbarScreenPlacement.pinned(selection).pinnedSelection, selection)
    }

    // MARK: - 状态菜单子菜单（2026-08-26 入口从设置窗口搬到菜单）

    private let screens = [(uuid: "A", title: "内建显示器"), (uuid: "B", title: "LG HDR 4K")]

    func testMenuHiddenWithSingleScreenAndFollowMouse() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: .followMouse,
            connectedScreens: [(uuid: "A", title: "内建显示器")]
        )
        XCTAssertTrue(presentation.isHidden)
    }

    /// 固定到外接屏后把它拔掉 → 只剩一块屏，但整行必须还在，否则再也切不回「跟随鼠标」。
    func testMenuVisibleWithSingleScreenWhilePinned() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: .pinned(PinnedScreenSelection(uuid: "B", name: "LG HDR 4K")),
            connectedScreens: [(uuid: "A", title: "内建显示器")]
        )
        XCTAssertFalse(presentation.isHidden)
    }

    func testMenuVisibleWithTwoScreens() {
        let presentation = TaskbarScreenMenuPresentation(placement: .followMouse, connectedScreens: screens)
        XCTAssertFalse(presentation.isHidden)
    }

    func testFollowMouseIsFirstItemAndCheckedWhenNotPinned() {
        let presentation = TaskbarScreenMenuPresentation(placement: .followMouse, connectedScreens: screens)
        XCTAssertEqual(presentation.items.count, 4)
        XCTAssertEqual(presentation.items[0].selection, .followMouse)
        XCTAssertTrue(presentation.items[0].isChecked)
        XCTAssertEqual(
            presentation.items.map(\.selection),
            [.followMouse, .screen(uuid: "A"), .screen(uuid: "B"), .allScreens]
        )
        XCTAssertEqual(presentation.items.filter(\.isChecked).count, 1)
    }

    func testPinnedScreenIsTheOnlyCheckedItem() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: .pinned(PinnedScreenSelection(uuid: "B", name: "LG HDR 4K")),
            connectedScreens: screens
        )
        XCTAssertEqual(presentation.items.count, 4)
        XCTAssertFalse(presentation.items[0].isChecked)
        XCTAssertEqual(presentation.items.filter(\.isChecked).map(\.selection), [.screen(uuid: "B")])
    }

    /// 固定的屏此刻不在场：末尾补一项且保持选中，选择不丢。
    func testAbsentPinnedScreenGetsTrailingCheckedItem() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: .pinned(PinnedScreenSelection(uuid: "Z", name: "Dell U2720Q")),
            connectedScreens: screens
        )
        XCTAssertEqual(presentation.items.count, 5)
        XCTAssertEqual(presentation.items.last?.selection, .screen(uuid: "Z"))
        XCTAssertEqual(presentation.items.filter(\.isChecked).map(\.selection), [.screen(uuid: "Z")])
        // 文案随语言变，只锁住那块屏的名字被带进了标题。
        XCTAssertTrue(presentation.items.last?.title.contains("Dell U2720Q") == true)
    }

    // MARK: - ③④ 所有屏幕档（2026-09-02）

    func testAllScreensIsTheOnlyCheckedItemAndSitsAfterScreens() {
        let presentation = TaskbarScreenMenuPresentation(placement: .allScreens, connectedScreens: screens)
        XCTAssertEqual(presentation.items.filter(\.isChecked).map(\.selection), [.allScreens])
        XCTAssertEqual(presentation.items.last?.selection, .allScreens)
    }

    /// 开着「所有屏幕」拔到只剩一块屏：整行必须还在，否则切不回「跟随鼠标」。
    func testMenuVisibleWithSingleScreenWhileAllScreens() {
        let presentation = TaskbarScreenMenuPresentation(
            placement: .allScreens,
            connectedScreens: [(uuid: "A", title: "内建显示器")]
        )
        XCTAssertFalse(presentation.isHidden)
    }

    /// ④ 行随里程碑二上；在那之前只有存值已是 ④ 才显示（保证有勾选项）。
    func testPerDisplayRowOnlyAppearsWhenSelected() {
        let plain = TaskbarScreenMenuPresentation(placement: .followMouse, connectedScreens: screens)
        XCTAssertFalse(plain.items.contains { $0.selection == .allScreensPerDisplay })
        let selected = TaskbarScreenMenuPresentation(placement: .allScreensPerDisplay, connectedScreens: screens)
        XCTAssertEqual(selected.items.filter(\.isChecked).map(\.selection), [.allScreensPerDisplay])
    }

    func testSelectionTokenRoundTrips() {
        typealias Selection = TaskbarScreenMenuPresentation.Selection
        let all: [Selection] = [.followMouse, .allScreens, .allScreensPerDisplay, .screen(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")]
        for selection in all {
            XCTAssertEqual(Selection(token: selection.token), selection)
        }
        XCTAssertNil(Selection(token: "screen:"))
        XCTAssertNil(Selection(token: "garbage"))
        XCTAssertEqual(Selection.screen(uuid: "A").screenUUID, "A")
        XCTAssertNil(Selection.allScreens.screenUUID)
    }
}

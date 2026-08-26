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
    }

    func testModeAndSelectionAccessors() {
        XCTAssertEqual(TaskbarScreenPlacement.followMouse.mode, .followMouse)
        XCTAssertNil(TaskbarScreenPlacement.followMouse.pinnedSelection)
        let selection = PinnedScreenSelection(uuid: "A", name: "LG")
        XCTAssertEqual(TaskbarScreenPlacement.pinned(selection).mode, .pinned)
        XCTAssertEqual(TaskbarScreenPlacement.pinned(selection).pinnedSelection, selection)
    }
}

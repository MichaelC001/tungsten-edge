import XCTest

/// The native Dock's view-mode choice and fan overflow, locked against the measured screen
/// (1512 × 982, menu bar 33, Dock 61).
final class FolderViewResolutionTests: XCTestCase {
    private let measuredStage = StackStage.height(screenHeightBelowMenuBar: 982 - 33, barOccupiedHeight: 61)

    func testMeasuredStageHeight() {
        XCTAssertEqual(measuredStage, 710)
        XCTAssertEqual(StackStage.maxFanItems(stageHeight: measuredStage), 11)
    }

    func testAutomaticFansUpToTenFilesOnTheMeasuredScreen() {
        XCTAssertEqual(FolderViewResolution.resolve(mode: .automatic, fileCount: 9, stageHeight: measuredStage),
                       .fan(fileItems: 9, hiddenCount: 0))
        XCTAssertEqual(FolderViewResolution.resolve(mode: .automatic, fileCount: 10, stageHeight: measuredStage),
                       .fan(fileItems: 10, hiddenCount: 0))
        XCTAssertEqual(FolderViewResolution.resolve(mode: .automatic, fileCount: 11, stageHeight: measuredStage), .grid)
        XCTAssertEqual(FolderViewResolution.resolve(mode: .automatic, fileCount: 12, stageHeight: measuredStage), .grid)
    }

    func testEmptyFolderFansToTheFinderCellAlone() {
        XCTAssertEqual(FolderViewResolution.resolve(mode: .automatic, fileCount: 0, stageHeight: measuredStage),
                       .fan(fileItems: 0, hiddenCount: 0))
    }

    func testForcedFanOverflowsIntoMoreInFinder() {
        // Measured: a forced fan of 30 files shows 11 items, the top one "20 More in Finder".
        XCTAssertEqual(FolderViewResolution.resolve(mode: .fan, fileCount: 30, stageHeight: measuredStage),
                       .fan(fileItems: 10, hiddenCount: 20))
        // One past the edge leaves exactly one hidden.
        XCTAssertEqual(FolderViewResolution.resolve(mode: .fan, fileCount: 11, stageHeight: measuredStage),
                       .fan(fileItems: 10, hiddenCount: 1))
    }

    func testExplicitGridAndListIgnoreTheCount() {
        XCTAssertEqual(FolderViewResolution.resolve(mode: .grid, fileCount: 1, stageHeight: measuredStage), .grid)
        XCTAssertEqual(FolderViewResolution.resolve(mode: .list, fileCount: 1, stageHeight: measuredStage), .list)
        XCTAssertEqual(FolderViewResolution.resolve(mode: .list, fileCount: 500, stageHeight: measuredStage), .list)
    }

    func testMoreInFinderCopySeparatesOne() {
        XCTAssertEqual(FolderViewResolution.moreInFinderCopy(hiddenCount: 1), .one)
        XCTAssertEqual(FolderViewResolution.moreInFinderCopy(hiddenCount: 2), .many)
        XCTAssertEqual(FolderViewResolution.moreInFinderCopy(hiddenCount: 20), .many)
    }
}

/// FolderViewMode: the default and the persisted / menu shape.
final class FolderViewModeTests: XCTestCase {
    func testDefaultIsAutomaticAsOnTheNativeDock() {
        XCTAssertEqual(FolderViewMode.default, .automatic)
    }

    func testMenuOrderIsTheNativeOrder() {
        XCTAssertEqual(FolderViewMode.allCases, [.fan, .grid, .list, .automatic])
    }

    func testRawValuesRoundTrip() {
        for mode in FolderViewMode.allCases {
            XCTAssertEqual(FolderViewMode(rawValue: mode.rawValue), mode)
        }
        XCTAssertNil(FolderViewMode(rawValue: ""))
    }
}

final class StackReopenCooldownTests: XCTestCase {
    func testSamePathIsRefusedForATenthOfASecond() {
        var cooldown = StackReopenCooldown()
        cooldown.noteClosed(path: "/a", at: 10)
        XCTAssertFalse(cooldown.allowsOpening(path: "/a", at: 10.05))
        XCTAssertTrue(cooldown.allowsOpening(path: "/a", at: 10.15))
    }

    func testAnotherPathOpensAtOnce() {
        var cooldown = StackReopenCooldown()
        cooldown.noteClosed(path: "/a", at: 10)
        XCTAssertTrue(cooldown.allowsOpening(path: "/b", at: 10.01))
    }

    func testNothingClosedAllowsEverything() {
        XCTAssertTrue(StackReopenCooldown().allowsOpening(path: "/a", at: 0))
    }
}

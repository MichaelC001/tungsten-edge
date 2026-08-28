import XCTest

final class FullscreenClassificationTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    // 回归：Finder 桌面伪窗口（role=AXScrollArea，frame 恰好等于整屏）不得判为全屏
    func testDesktopPseudoWindowWithExactScreenFrameIsNotFullscreen() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXScrollArea", isAXFullscreen: false, windowFrame: screen, screenCGFrame: screen))
    }

    func testUnreadableRoleIsNotFullscreenEvenWithExactScreenFrame() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: nil, isAXFullscreen: false, windowFrame: screen, screenCGFrame: screen))
    }

    func testUnreadableRoleIsNotFullscreenEvenWithAXFullscreenFlag() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: nil, isAXFullscreen: true, windowFrame: nil, screenCGFrame: screen))
    }

    func testNativeFullscreenWindowIsFullscreen() {
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: screen, screenCGFrame: screen))
    }

    func testNativeFullscreenWithUnreadableFrameIsFullscreen() {
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: nil, screenCGFrame: screen))
    }

    func testNativeFullscreenOnAnotherScreenIsNotFullscreenHere() {
        let otherScreen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: otherScreen, screenCGFrame: screen))
    }

    // 无 AXFullScreen 标志的无边框全屏（游戏/HTML5）仍走 frame≈整屏兜底
    func testBorderlessScreenSizedWindowIsFullscreen() {
        let nearScreen = screen.insetBy(dx: 2, dy: 2)
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: nearScreen, screenCGFrame: screen))
    }

    func testOrdinaryWindowIsNotFullscreen() {
        let partial = CGRect(x: 253, y: 125, width: 1127, height: 689)
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: partial, screenCGFrame: screen))
    }

    func testRealWindowWithUnreadableFrameIsNotFullscreen() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: nil, screenCGFrame: screen))
    }

    // MARK: - 常驻所有桌面的成员资格（issue #19）

    func testMembershipIsHealthyWhenWindowCoversEveryDesktop() {
        XCTAssertEqual(
            AllSpacesMembership.missingSpaceIDs(windowSpaceIDs: [1, 3, 1020], desktopSpaceIDs: [1, 3, 1020]),
            [])
    }

    // 这就是 issue #19 的症状：退全屏之后只剩当前桌面
    func testMembershipCollapsedToCurrentDesktopIsReported() {
        XCTAssertEqual(
            AllSpacesMembership.missingSpaceIDs(windowSpaceIDs: [1], desktopSpaceIDs: [1, 3, 1020]),
            [3, 1020])
    }

    // 窗口多挂了一个全屏空间不算问题（进全屏那一瞬间就是这个样子）
    func testExtraFullscreenSpaceMembershipIsNotAProblem() {
        XCTAssertEqual(
            AllSpacesMembership.missingSpaceIDs(windowSpaceIDs: [1, 3, 1013], desktopSpaceIDs: [1, 3]),
            [])
    }

    // 单桌面谈不上「丢桌面」，永远不要触发修复
    func testSingleDesktopNeverReportsMissing() {
        XCTAssertEqual(
            AllSpacesMembership.missingSpaceIDs(windowSpaceIDs: [], desktopSpaceIDs: [1]),
            [])
    }

    func testEmptyDesktopListNeverReportsMissing() {
        XCTAssertEqual(
            AllSpacesMembership.missingSpaceIDs(windowSpaceIDs: [1], desktopSpaceIDs: []),
            [])
    }

    // 修复单次不保证成功，必须允许重试，但不能无限重试
    func testRepairRetriesAreBounded() {
        XCTAssertTrue(AllSpacesMembership.shouldRetry(attempt: 0))
        XCTAssertTrue(AllSpacesMembership.shouldRetry(attempt: 2))
        XCTAssertFalse(AllSpacesMembership.shouldRetry(attempt: 3))
        XCTAssertFalse(AllSpacesMembership.shouldRetry(attempt: 4))
    }
}

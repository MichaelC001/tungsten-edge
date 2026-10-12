import XCTest
@testable import macos_dock_cc_v2

final class DrawerAppDropTests: XCTestCase {

    func testNewMemberGoesFirst() {
        XCTAssertEqual(DrawerAppDrop.frontOrder(existing: ["a", "b"], dropped: ["new"]),
                       ["new", "a", "b"])
    }

    func testExistingMemberMovesToFront() {
        XCTAssertEqual(DrawerAppDrop.frontOrder(existing: ["a", "b", "c"], dropped: ["b"]),
                       ["b", "a", "c"])
    }

    func testFrontMemberStaysPut() {
        XCTAssertEqual(DrawerAppDrop.frontOrder(existing: ["a", "b"], dropped: ["a"]),
                       ["a", "b"])
    }

    func testSeveralKeepDragOrderAndDedupe() {
        XCTAssertEqual(DrawerAppDrop.frontOrder(existing: ["a", "b", "c"],
                                                dropped: ["c", "x", "c", "", "a"]),
                       ["c", "x", "a", "b"])
    }

    func testEmptyDropKeepsOrder() {
        XCTAssertEqual(DrawerAppDrop.frontOrder(existing: ["a", "b"], dropped: []), ["a", "b"])
    }

    func testAcceptsOnlyAppsInsideTheZone() {
        let capsule = CGRect(x: 100, y: 0, width: 60, height: 60)
        let zone = capsule.insetBy(dx: -DrawerAppDrop.capsuleTolerance, dy: -DrawerAppDrop.capsuleTolerance)
        XCTAssertTrue(DrawerAppDrop.accepts(containsApplication: true, point: CGPoint(x: 130, y: 30), zone: zone))
        // Inside the tolerance, e.g. the gap between bar and capsule.
        XCTAssertTrue(DrawerAppDrop.accepts(containsApplication: true, point: CGPoint(x: 93, y: 30), zone: zone))
        XCTAssertFalse(DrawerAppDrop.accepts(containsApplication: true, point: CGPoint(x: 91, y: 30), zone: zone))
        XCTAssertFalse(DrawerAppDrop.accepts(containsApplication: false, point: CGPoint(x: 130, y: 30), zone: zone))
    }
}

extension DrawerAppDropTests {
    func testPlacementFollowsTheCellUnderThePointer() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 100, height: 100),
                      "b": CGRect(x: 100, y: 0, width: 100, height: 100)]
        let order = ["a", "b"]
        XCTAssertEqual(DrawerAppDrop.placement(at: CGPoint(x: 20, y: 50), frames: frames, order: order), .before("a"))
        XCTAssertEqual(DrawerAppDrop.placement(at: CGPoint(x: 80, y: 50), frames: frames, order: order), .after("a"))
        XCTAssertEqual(DrawerAppDrop.placement(at: CGPoint(x: 120, y: 50), frames: frames, order: order), .before("b"))
        // Off every cell (title row, space past the last cell): the end.
        XCTAssertEqual(DrawerAppDrop.placement(at: CGPoint(x: 150, y: 150), frames: frames, order: order), .end)
    }

    func testOrderAtEveryPlacement() {
        let existing = ["a", "b", "c"]
        XCTAssertEqual(DrawerAppDrop.order(existing: existing, dropped: ["x"], placement: .end), ["a", "b", "c", "x"])
        XCTAssertEqual(DrawerAppDrop.order(existing: existing, dropped: ["x"], placement: .before("b")), ["a", "x", "b", "c"])
        XCTAssertEqual(DrawerAppDrop.order(existing: existing, dropped: ["x"], placement: .after("b")), ["a", "b", "x", "c"])
        XCTAssertEqual(DrawerAppDrop.order(existing: existing, dropped: ["x", "y"], placement: .after("c")), ["a", "b", "c", "x", "y"])
    }

    func testExistingMemberMovesBesideTheTarget() {
        XCTAssertEqual(DrawerAppDrop.order(existing: ["a", "b", "c"], dropped: ["a"], placement: .after("c")), ["b", "c", "a"])
        XCTAssertEqual(DrawerAppDrop.order(existing: ["a", "b", "c"], dropped: ["c"], placement: .before("a")), ["c", "a", "b"])
    }

    func testTargetThatIsNoMemberLandsAtTheEnd() {
        XCTAssertEqual(DrawerAppDrop.order(existing: ["a", "b"], dropped: ["x"], placement: .before("gone")), ["a", "b", "x"])
        // Dropping onto the cell being moved itself: it has left the order, so it goes last.
        XCTAssertEqual(DrawerAppDrop.order(existing: ["a", "b"], dropped: ["a"], placement: .after("a")), ["b", "a"])
    }

    func testPlainFilesAreRefused() {
        let zone = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertFalse(DrawerAppDrop.accepts(containsApplication: false, point: CGPoint(x: 150, y: 100), zone: zone))
    }
}

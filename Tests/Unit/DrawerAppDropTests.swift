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

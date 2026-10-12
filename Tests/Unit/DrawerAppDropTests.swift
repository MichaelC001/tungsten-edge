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

// MARK: - The make-way slot of an outside drag over the open drawer

extension DrawerAppDropTests {
    /// a | x(slot) | b, one row of 100pt cells.
    private var slotFrames: [String: CGRect] {
        ["a": CGRect(x: 0, y: 0, width: 100, height: 100),
         "x": CGRect(x: 100, y: 0, width: 100, height: 100),
         "b": CGRect(x: 200, y: 0, width: 100, height: 100)]
    }

    func testSlotFollowsTheMidlineOfAnotherCell() {
        let order = ["a", "x", "b"]
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: .after("a"), point: CGPoint(x: 20, y: 50),
                                                    frames: slotFrames, displayOrder: order, ghostIDs: ["x"]),
                       .before("a"))
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: .after("a"), point: CGPoint(x: 280, y: 50),
                                                    frames: slotFrames, displayOrder: order, ghostIDs: ["x"]),
                       .after("b"))
    }

    func testSlotStaysPutUnderThePointerAndOffEveryCell() {
        let order = ["a", "x", "b"]
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: .after("a"), point: CGPoint(x: 150, y: 50),
                                                    frames: slotFrames, displayOrder: order, ghostIDs: ["x"]),
                       .after("a"))
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: .after("a"), point: CGPoint(x: 150, y: 300),
                                                    frames: slotFrames, displayOrder: order, ghostIDs: ["x"]),
                       .after("a"))
    }

    func testFirstHoverOffEveryCellOpensTheSlotAtTheEnd() {
        let frames = ["a": CGRect(x: 0, y: 0, width: 100, height: 100)]
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: nil, point: CGPoint(x: 150, y: 50),
                                                    frames: frames, displayOrder: ["a"], ghostIDs: ["new"]),
                       .end)
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: nil, point: CGPoint(x: 20, y: 50),
                                                    frames: frames, displayOrder: ["a"], ghostIDs: ["new"]),
                       .before("a"))
    }

    /// An app already in the drawer, entering over its own cell: the slot is where the cell was.
    func testFirstHoverOverTheDraggedAppsOwnCellKeepsItWhereItIs() {
        let order = ["a", "x", "b"]
        let placement = DrawerAppDrop.hoverPlacement(current: nil, point: CGPoint(x: 150, y: 50),
                                                     frames: slotFrames, displayOrder: order, ghostIDs: ["x"])
        XCTAssertEqual(placement, .before("b"))
        XCTAssertEqual(ExternalDrawerGhost(ids: ["x"], placement: placement).displayOrder(visibleMembers: order), order)
        // The last cell has nothing after it.
        XCTAssertEqual(DrawerAppDrop.hoverPlacement(current: nil, point: CGPoint(x: 250, y: 50),
                                                    frames: slotFrames, displayOrder: order, ghostIDs: ["b"]),
                       .end)
    }

    func testGhostOrderMovesAMemberAndInsertsANewcomer() {
        let members = ["a", "b", "c"]
        // Already a member: its cell empties and the slot opens where the pointer is.
        XCTAssertEqual(ExternalDrawerGhost(ids: ["a"], placement: .after("c")).displayOrder(visibleMembers: members),
                       ["b", "c", "a"])
        // New: one more cell; the order the drop commits is the one shown.
        let ghost = ExternalDrawerGhost(ids: ["x", "y"], placement: .before("b"))
        XCTAssertEqual(ghost.displayOrder(visibleMembers: members), ["a", "x", "y", "b", "c"])
        XCTAssertEqual(ghost.displayOrder(visibleMembers: members),
                       DrawerAppDrop.order(existing: members, dropped: ghost.ids, placement: ghost.placement))
    }

    /// `.after(a)` and `.before(b)` are one slot: the view compares orders, not placements.
    func testTwoPlacementsCanShowTheSameSlot() {
        let members = ["a", "b"]
        XCTAssertNotEqual(DrawerAppDrop.Placement.after("a"), .before("b"))
        XCTAssertEqual(ExternalDrawerGhost(ids: ["x"], placement: .after("a")).displayOrder(visibleMembers: members),
                       ExternalDrawerGhost(ids: ["x"], placement: .before("b")).displayOrder(visibleMembers: members))
    }
}

import XCTest

/// The stack grid's shape rule against the native Dock's own answers (macOS 27, 1352×878 screen).
final class StackPopupGeometryTests: XCTestCase {
    /// Limits of the measured screen: 7 columns, 4 rows once scrolling, 5 rows fit above the Dock.
    private let measured = StackGridLayout.Limits(maxColumns: 7, nominalRows: 4, fitRows: 5, fitRowsWithNote: 5)

    func testShapesMatchTheNativeDock() {
        let native: [(cells: Int, columns: Int, rows: Int)] = [
            (3, 3, 1), (7, 4, 2), (8, 4, 2), (9, 3, 3), (10, 5, 2), (11, 4, 3), (12, 4, 3),
            (13, 5, 3), (14, 5, 3), (15, 5, 3), (16, 4, 4), (17, 6, 3), (18, 6, 3), (19, 5, 4),
            (20, 5, 4), (21, 6, 4), (22, 6, 4), (23, 6, 4), (24, 6, 4), (25, 5, 5), (26, 7, 4),
            (27, 7, 4), (28, 7, 4),
        ]
        for point in native {
            XCTAssertEqual(StackGridLayout.resolve(cellCount: point.cells, limits: measured, hasNote: false),
                           .init(columns: point.columns, visibleRows: point.rows, scrolls: false),
                           "\(point.cells) cells")
        }
    }

    func testOverCapacityScrollsAtFullWidth() {
        for cells in [29, 30, 36, 67] {
            XCTAssertEqual(StackGridLayout.resolve(cellCount: cells, limits: measured, hasNote: false),
                           .init(columns: 7, visibleRows: 4, scrolls: true), "\(cells) cells")
        }
    }

    func testLimitsOfTheMeasuredScreen() {
        // Plate top 8pt under the menu bar, arrow tip 3pt above a Dock whose top edge is at 57pt.
        let limits = StackGridLayout.limits(screenSize: CGSize(width: 1352, height: 878), availablePlateHeight: 772)
        XCTAssertEqual(limits, measured)
    }

    func testAShortScreenStillYieldsAGrid() {
        let limits = StackGridLayout.limits(screenSize: CGSize(width: 800, height: 400), availablePlateHeight: 150)
        XCTAssertEqual(limits.fitRows, 1)
        let one = StackGridLayout.resolve(cellCount: 2, limits: limits, hasNote: false)
        XCTAssertEqual(one, .init(columns: 2, visibleRows: 1, scrolls: false))
        let many = StackGridLayout.resolve(cellCount: 40, limits: limits, hasNote: false)
        XCTAssertEqual(many.visibleRows, 1)
        XCTAssertTrue(many.scrolls)
        XCTAssertEqual(many.columns, limits.maxColumns)
    }

    /// A status line takes its height only when there is one: the same 25 cells stay the native
    /// 5×5 without it and fall back to 7×4 with it, where a fifth row would no longer fit.
    func testAStatusLineCostsRowsOnlyWhenPresent() {
        // A tall bar on the measured screen: 719pt for the plate, five rows without a note.
        let limits = StackGridLayout.limits(screenSize: CGSize(width: 1352, height: 878), availablePlateHeight: 719)
        XCTAssertEqual(limits.fitRows, 5)
        XCTAssertEqual(limits.fitRowsWithNote, 4)
        XCTAssertEqual(StackGridLayout.resolve(cellCount: 25, limits: limits, hasNote: false),
                       .init(columns: 5, visibleRows: 5, scrolls: false))
        XCTAssertEqual(StackGridLayout.resolve(cellCount: 25, limits: limits, hasNote: true),
                       .init(columns: 7, visibleRows: 4, scrolls: false))
        for hasNote in [false, true] {
            for cells in 1...80 {
                let shape = StackGridLayout.resolve(cellCount: cells, limits: limits, hasNote: hasNote)
                let plate = StackPopupMetrics.plateSize(columns: shape.columns, rows: shape.visibleRows, hasNote: hasNote)
                XCTAssertLessThanOrEqual(plate.height, 719, "\(cells) cells, note \(hasNote)")
            }
        }
    }

    func testAStatusLineWidensANarrowPlate() {
        XCTAssertEqual(StackGridLayout.resolve(cellCount: 1, limits: measured, hasNote: true),
                       .init(columns: 3, visibleRows: 1, scrolls: false))
        XCTAssertEqual(StackGridLayout.resolve(cellCount: 1, limits: measured, hasNote: false),
                       .init(columns: 1, visibleRows: 1, scrolls: false))
    }

    func testSizesAreDerivedFromTheShape() {
        // The native 4×3 plate measured 546 wide (+ hairline) and 428 tall.
        let plate = StackPopupMetrics.plateSize(columns: 4, rows: 3, hasNote: false)
        XCTAssertEqual(plate, CGSize(width: 546, height: 428))
        XCTAssertEqual(StackPopupMetrics.panelSize(forPlate: plate), CGSize(width: 626, height: 516))
    }

    func testOutlineHangsTheArrowBelowThePlate() {
        let plate = CGSize(width: 546, height: 428)
        let plain = StackPopupOutline.path(plateSize: plate, arrowCenterX: nil).boundingBoxOfPath
        XCTAssertEqual(plain.origin, .zero)
        XCTAssertEqual(plain.width, plate.width, accuracy: 0.001)
        XCTAssertEqual(plain.height, plate.height, accuracy: 0.001)
        let box = StackPopupOutline.path(plateSize: plate, arrowCenterX: 273).boundingBoxOfPath
        XCTAssertEqual(box.minY, 0)
        XCTAssertEqual(box.width, plate.width, accuracy: 0.001)
        XCTAssertEqual(box.maxY, plate.height + StackPopupMetrics.arrowHeight, accuracy: 0.05)
    }

    func testArrowStaysOffTheCorners() {
        XCTAssertEqual(StackPopupOutline.clampedArrowCenterX(2, plateWidth: 546), 42)
        XCTAssertEqual(StackPopupOutline.clampedArrowCenterX(540, plateWidth: 546), 504)
        XCTAssertEqual(StackPopupOutline.clampedArrowCenterX(300, plateWidth: 546), 300)
        // Too narrow for a clamp range: centre it.
        XCTAssertEqual(StackPopupOutline.clampedArrowCenterX(10, plateWidth: 80), 40)
    }
}

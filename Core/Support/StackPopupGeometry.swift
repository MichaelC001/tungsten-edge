import CoreGraphics
import Foundation

/// Every number of the folder / shelf / Trash popup, measured off the native Dock's stack grid
/// (macOS 27, AX frames plus screenshots over a solid backdrop). They are the look, not tuning
/// knobs: change one only against a new native measurement.
enum StackPopupMetrics {
    static let cell: CGFloat = 128
    static let iconSize: CGFloat = 100
    static let iconTop: CGFloat = 6
    static let labelSize: CGFloat = 13
    /// Width a name too long for the cell is truncated to (one that fits the cell is not cut).
    static let labelWidth: CGFloat = 120
    static let labelHeight: CGFloat = 16

    static let sidePadding: CGFloat = 17
    /// The title row above the grid.
    static let headerHeight: CGFloat = 32
    static let bottomPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 26

    static let titleSize: CGFloat = 14
    /// Vertical centre of the title's line box, from the plate's top edge.
    static let titleCenterY: CGFloat = 18
    static let backButtonOrigin = CGPoint(x: 15.5, y: 7)
    static let backButtonSize = CGSize(width: 21, height: 22)

    /// A status line between title and grid (no native counterpart: empty shelf, Trash state).
    static let noteHeight: CGFloat = 36

    static let arrowHeight: CGFloat = 8
    /// Height the arrow would have with a sharp tip; its sides run at 45°.
    static let arrowSharpHeight: CGFloat = 9.75
    static let arrowTipRadius: CGFloat = 4.2
    static let arrowBaseRadius: CGFloat = 14
    /// Arrow tip to the anchor's top edge.
    static let tipGap: CGFloat = 3
    /// The plate's distance to the screen's left / right edge (native reading) …
    static let screenMargin: CGFloat = 31
    /// … which gives way, down to this, when the anchor itself sits at the edge: a plate held
    /// 31pt in could not put its arrow on the first or last chip of a full-width bar.
    static let minimumScreenMargin: CGFloat = 4
    /// Closest the arrow's centre comes to the plate's side: the corner radius plus the arrow's
    /// half base (9.75) and its base fillet's tangent length (5.8). Closer and it enters the arc.
    static let arrowInset: CGFloat = 42
    /// Transparent border of the popup window around the plate. The glass draws its own shadow,
    /// which reaches ~38pt out.
    static let panelMargin: CGFloat = 40
    /// The scroller sits in the plate's right padding, not over the last column.
    static let scrollerGutter: CGFloat = 14

    /// `cell` is the grid's cell side: the native one, or the drawer's smaller one.
    static func plateSize(columns: Int, rows: Int, hasNote: Bool, cell: CGFloat = StackPopupMetrics.cell) -> CGSize {
        CGSize(width: CGFloat(columns) * cell + 2 * sidePadding,
               height: headerHeight + (hasNote ? noteHeight : 0) + CGFloat(rows) * cell + bottomPadding)
    }

    /// Size of the popup window for a plate: the transparent border plus the arrow below it.
    static func panelSize(forPlate plate: CGSize) -> CGSize {
        CGSize(width: plate.width + 2 * panelMargin, height: plate.height + arrowHeight + 2 * panelMargin)
    }
}

/// One grid cell's numbers. The folder / shelf / Trash popups use `native`; the drawer draws the
/// same cell at three quarters (owner 2026-10-04: the native size made the drawer too large). Its
/// row and column limits stay the native counts, so the whole plate is three quarters too.
struct StackCellMetrics: Equatable {
    var cell: CGFloat
    var iconSize: CGFloat
    var iconTop: CGFloat
    var labelSize: CGFloat
    var labelWidth: CGFloat
    var labelHeight: CGFloat

    static let native = StackCellMetrics(
        cell: StackPopupMetrics.cell, iconSize: StackPopupMetrics.iconSize, iconTop: StackPopupMetrics.iconTop,
        labelSize: StackPopupMetrics.labelSize, labelWidth: StackPopupMetrics.labelWidth,
        labelHeight: StackPopupMetrics.labelHeight)
    static let drawer = StackCellMetrics(cell: 96, iconSize: 75, iconTop: 5, labelSize: 12, labelWidth: 90, labelHeight: 15)
}

/// How many columns and rows the grid takes for a cell count — the native Dock's rule, derived
/// from 22 measured counts (`StackPopupGeometryTests`). Never replace it with a measured size.
enum StackGridLayout {
    struct Limits: Equatable {
        var maxColumns: Int
        /// Rows the native grid shows once it scrolls; with `maxColumns` it sets the capacity.
        var nominalRows: Int
        /// Rows that physically fit above the anchor. A non-scrolling grid may exceed
        /// `nominalRows` up to this (the native 5×5 on a screen whose capacity is 7×4).
        var fitRows: Int
        /// The same with a status line taking its height off the top.
        var fitRowsWithNote: Int
    }

    struct Result: Equatable {
        var columns: Int
        var visibleRows: Int
        var scrolls: Bool
    }

    /// `maxColumns` / `nominalRows` follow the screen; the 0.7 share is fitted to the one measured
    /// screen (1352×878 → 7 × 4) and extrapolated to others.
    static func limits(screenSize: CGSize, availablePlateHeight: CGFloat) -> Limits {
        let m = StackPopupMetrics.self
        let chromeHeight = m.headerHeight + m.bottomPadding
        let shareColumns = Int(((0.7 * screenSize.width - 2 * m.sidePadding) / m.cell).rounded(.down))
        let fitColumns = Int(((screenSize.width - 2 * m.screenMargin - 2 * m.sidePadding) / m.cell).rounded(.down))
        let nominalRows = Int(((0.7 * screenSize.height - chromeHeight) / m.cell).rounded(.down))
        func rows(in height: CGFloat) -> Int { max(1, Int(((height - chromeHeight) / m.cell).rounded(.down))) }
        return Limits(maxColumns: max(1, min(max(3, shareColumns), fitColumns)),
                      nominalRows: max(2, nominalRows),
                      fitRows: rows(in: availablePlateHeight),
                      fitRowsWithNote: rows(in: availablePlateHeight - m.noteHeight))
    }

    /// A status line needs room to be read; the native grid never shows one.
    static let noteMinColumns = 3

    /// The grid's shape. A status line (`hasNote`) costs the rows it displaces and widens a
    /// narrow plate to `noteMinColumns`; without one this is the native rule untouched.
    static func resolve(cellCount: Int, limits: Limits, hasNote: Bool) -> Result {
        guard hasNote else { return shape(cellCount: cellCount, limits: limits, fitRows: limits.fitRows) }
        let natural = shape(cellCount: cellCount, limits: limits, fitRows: limits.fitRowsWithNote)
        let columns = min(max(natural.columns, noteMinColumns), max(natural.columns, limits.maxColumns))
        guard columns > natural.columns else { return natural }
        let rows = Int((Double(max(1, cellCount)) / Double(columns)).rounded(.up))
        return Result(columns: columns, visibleRows: min(rows, natural.visibleRows), scrolls: natural.scrolls)
    }

    private static func shape(cellCount: Int, limits: Limits, fitRows: Int) -> Result {
        let count = max(1, cellCount)
        let pageRows = max(1, min(limits.nominalRows, fitRows))
        let capacity = limits.maxColumns * pageRows
        guard count <= capacity else {
            return Result(columns: limits.maxColumns, visibleRows: pageRows, scrolls: true)
        }
        // Fewest empty cells among near-square shapes (rows ≤ columns ≤ rows + 3) within the
        // capacity; ascending rows makes a tie go to the flatter shape.
        var best: (columns: Int, rows: Int, empty: Int)?
        for rows in 1...max(1, fitRows) {
            let columns = max(rows, Int((Double(count) / Double(rows)).rounded(.up)))
            guard columns <= min(limits.maxColumns, rows + 3), columns * rows <= capacity else { continue }
            let empty = columns * rows - count
            if best == nil || empty < best!.empty { best = (columns, rows, empty) }
        }
        if let best { return Result(columns: best.columns, visibleRows: best.rows, scrolls: false) }
        let rows = Int((Double(count) / Double(limits.maxColumns)).rounded(.up))
        return Result(columns: limits.maxColumns, visibleRows: min(rows, pageRows), scrolls: rows > pageRows)
    }
}

/// The drawer's grid: the stack rule, held still while a drag is converting a chip in or out.
/// A conversion adds or removes a member before the release decides anything; reshaping the
/// grid on that (4 cells are 2 × 2, 5 are 3 × 2) would resize the plate under the pointer and
/// flip the enter / leave test that caused it.
enum DrawerGridShape {
    struct Result: Equatable {
        var layout: StackGridLayout.Result
        /// The empty drawer's hint line.
        var showsHint: Bool
    }

    /// Visible members with the conversion in flight undone: a chip converted in is not counted
    /// yet, one converted out still is. By id, never ±1 — both drag-out modes remove placement.
    static func settledCount(visibleIDs: [String], convertedInID: String?, convertedOutID: String?) -> Int {
        var ids = Set(visibleIDs)
        if let convertedInID { ids.remove(convertedInID) }
        if let convertedOutID { ids.insert(convertedOutID) }
        return ids.count
    }

    /// Columns come from `settledCount`; rows follow `actualCount` and never drop below one
    /// while the two differ. Only a drawer empty on both counts is the hint plate.
    static func resolve(settledCount: Int, actualCount: Int, limits: StackGridLayout.Limits) -> Result {
        if settledCount == actualCount {
            guard actualCount > 0 else {
                return Result(layout: .init(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false),
                              showsHint: true)
            }
            return Result(layout: StackGridLayout.resolve(cellCount: actualCount, limits: limits, hasNote: false),
                          showsHint: false)
        }
        let columns: Int
        let maxRows: Int
        if settledCount > 0 {
            let settled = StackGridLayout.resolve(cellCount: settledCount, limits: limits, hasNote: false)
            columns = settled.columns
            maxRows = settled.scrolls ? settled.visibleRows : limits.fitRows
        } else {
            columns = StackGridLayout.noteMinColumns
            maxRows = limits.fitRows
        }
        let rows = max(1, Int((Double(actualCount) / Double(columns)).rounded(.up)))
        let visibleRows = min(rows, max(1, maxRows))
        return Result(layout: .init(columns: columns, visibleRows: visibleRows, scrolls: rows > visibleRows),
                      showsHint: false)
    }
}

/// The plate's outline: a rounded rectangle with the arrow on its bottom edge. One path feeds both
/// the glass (`_setPath:`) and the frosted fallback's clip, so the two can never disagree.
enum StackPopupOutline {
    /// Keeps the arrow and its base fillets on the straight part of the bottom edge.
    static func clampedArrowCenterX(_ x: CGFloat, plateWidth: CGFloat) -> CGFloat {
        let inset = StackPopupMetrics.arrowInset
        guard plateWidth > 2 * inset else { return plateWidth / 2 }
        return min(max(x, inset), plateWidth - inset)
    }

    /// Top-left origin, y down; the arrow hangs below `plateSize.height`. `arrowCenterX == nil`
    /// draws the plate alone.
    static func path(plateSize: CGSize, arrowCenterX: CGFloat?) -> CGPath {
        let m = StackPopupMetrics.self
        let (w, h, r) = (plateSize.width, plateSize.height, min(m.cornerRadius, min(plateSize.width, plateSize.height) / 2))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: 0, y: h), radius: r)
        if let arrowCenterX {
            let cx = clampedArrowCenterX(arrowCenterX, plateWidth: w)
            let t = m.arrowSharpHeight
            path.addArc(tangent1End: CGPoint(x: cx + t, y: h), tangent2End: CGPoint(x: cx, y: h + t), radius: m.arrowBaseRadius)
            path.addArc(tangent1End: CGPoint(x: cx, y: h + t), tangent2End: CGPoint(x: cx - t, y: h), radius: m.arrowTipRadius)
            path.addArc(tangent1End: CGPoint(x: cx - t, y: h), tangent2End: CGPoint(x: 0, y: h), radius: m.arrowBaseRadius)
        }
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: r)
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: r)
        path.closeSubpath()
        return path
    }
}

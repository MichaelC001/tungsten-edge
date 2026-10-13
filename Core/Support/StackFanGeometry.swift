import CoreGraphics
import Foundation

/// The native Dock's stack stage: the screen area a stack may spread over. Bottom Dock only —
/// the bar never sits on a side.
enum StackStage {
    /// Height of one fan item, and the step the stage height is divided by to count fan slots.
    static let fanItemSide = 64

    /// `Int(0.8 × (screen height below the menu bar − the height the bar takes off the bottom))`.
    /// `barOccupiedHeight` is the bar plate's visible top above the screen's bottom edge.
    static func height(screenHeightBelowMenuBar: CGFloat, barOccupiedHeight: CGFloat) -> Int {
        Int(0.8 * (screenHeightBelowMenuBar - barOccupiedHeight))
    }

    /// How many fan items the stage holds, the last one included ("Open in Finder" / "N More").
    static func maxFanItems(stageHeight: Int) -> Int {
        max(1, stageHeight / fanItemSide)
    }
}

/// What a pinned folder's popup shows for one opening.
enum FolderPopupView: Equatable {
    /// `fileItems` items from the top of the sort, then one top cell: "Open in Finder" when
    /// `hiddenCount == 0`, else "N More in Finder" with N = `hiddenCount`.
    case fan(fileItems: Int, hiddenCount: Int)
    case grid
    case list
}

/// The native Dock's `expandUsingHandler` choice for a bottom Dock, from a measured
/// threshold: fan when `fileCount + 1 ≤ stageHeight / 64` (1512 × 982, menu bar 33, Dock 61 →
/// 10 files fan, 11 grid). It never looks at icon size.
enum FolderViewResolution {
    static func resolve(mode: FolderViewMode, fileCount: Int, stageHeight: Int) -> FolderPopupView {
        switch mode {
        case .list:
            return .list
        case .grid:
            return .grid
        case .fan:
            return fan(fileCount: fileCount, stageHeight: stageHeight)
        case .automatic:
            return fileCount + 1 <= stageHeight / StackStage.fanItemSide
                ? fan(fileCount: fileCount, stageHeight: stageHeight)
                : .grid
        }
    }

    /// A forced fan cuts at the stage: the top slot becomes "N More in Finder".
    static func fan(fileCount: Int, stageHeight: Int) -> FolderPopupView {
        let slots = StackStage.maxFanItems(stageHeight: stageHeight)
        let count = max(0, fileCount)
        if count + 1 <= slots { return .fan(fileItems: count, hiddenCount: 0) }
        let shown = slots - 1
        return .fan(fileItems: shown, hiddenCount: count - shown)
    }

    /// Which copy the overflow cell uses. The native strings keep "one more" separate (Italian
    /// words it differently).
    enum MoreInFinderCopy: Equatable { case one, many }

    static func moreInFinderCopy(hiddenCount: Int) -> MoreInFinderCopy {
        hiddenCount == 1 ? .one : .many
    }

    static func moreInFinderTitle(hiddenCount: Int) -> String {
        switch moreInFinderCopy(hiddenCount: hiddenCount) {
        case .one: return String(localized: "1 More in Finder")
        case .many: return String(format: String(localized: "%@ More in Finder"), "\(hiddenCount)")
        }
    }
}

/// Reopening the same stack is refused for 0.1s after it collapsed (`canBeExpanded`), per stack:
/// clicking another folder's chip closes the first on mouse-down and opens the second on
/// mouse-up, often well inside 0.1s.
struct StackReopenCooldown {
    static let interval: TimeInterval = 0.1
    private var lastClosed: (path: String, at: TimeInterval)?

    mutating func noteClosed(path: String, at time: TimeInterval) {
        lastClosed = (path, time)
    }

    func allowsOpening(path: String, at time: TimeInterval) -> Bool {
        guard let lastClosed, lastClosed.path == path else { return true }
        return time - lastClosed.at >= Self.interval
    }
}

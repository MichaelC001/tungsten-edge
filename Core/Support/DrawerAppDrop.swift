import CoreGraphics

/// Dropping app bundles from outside (Finder) onto the drawer capsule or into the open drawer:
/// where it lands and how the drawer order changes. The receiver is `DrawerAppDropReceiver`; the
/// commit is `PanelCoordinator.stashDroppedApplications`.
enum DrawerAppDrop {
    /// The capsule's drop zone reaches this far past its visible content, the same as the
    /// strip→capsule stash zone (`PanelCoordinator.dragDropZones`), so both drags agree on the
    /// gap between bar and capsule (also 8pt) belonging to the capsule.
    static let capsuleTolerance: CGFloat = 8

    /// Where dropped apps go in the drawer order. The capsule always lands them `.front`; a drop
    /// into the open drawer lands where the pointer was (`placement(at:frames:order:)`).
    enum Placement: Equatable {
        case front
        case before(String)
        case after(String)
        case end
    }

    /// Whether a hover may light the capsule and a release may land: at least one app bundle that
    /// is not inside a Trash, with the point inside `zone` (visible capsule + tolerance).
    static func accepts(containsApplication: Bool, point: CGPoint, zone: CGRect) -> Bool {
        containsApplication && zone.contains(point)
    }

    /// The drop point over the open drawer's grid: the cell under it decides, by its midline,
    /// whether the app goes before or after it; empty plate (title row, space past the last cell)
    /// appends at the end. `frames` and `point` share one coordinate space; `order` is the
    /// visible order and decides which cell wins when frames overlap mid-animation.
    static func placement(at point: CGPoint, frames: [String: CGRect], order: [String]) -> Placement {
        for id in order {
            guard let frame = frames[id], frame.contains(point) else { continue }
            return point.x > frame.midX ? .after(id) : .before(id)
        }
        return .end
    }

    /// The drawer order after a drop: the dropped ids first in drag order (deduped), everything
    /// else in its existing order. Ids not yet in `existing` are new members and go first too.
    static func frontOrder(existing: [String], dropped: [String]) -> [String] {
        order(existing: existing, dropped: dropped, placement: .front)
    }

    /// The drawer order after a drop at `placement`: the dropped ids (deduped, drag order kept)
    /// leave wherever they were and go in as one block — first, last, or beside the target cell.
    /// A target that is no longer a member lands them at the end.
    static func order(existing: [String], dropped: [String], placement: Placement) -> [String] {
        var seen = Set<String>()
        let block = dropped.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !block.isEmpty else { return existing }
        let rest = existing.filter { !seen.contains($0) }
        switch placement {
        case .front:
            return block + rest
        case .end:
            return rest + block
        case .before(let target):
            guard let index = rest.firstIndex(of: target) else { return rest + block }
            return Array(rest[..<index]) + block + Array(rest[index...])
        case .after(let target):
            guard let index = rest.firstIndex(of: target) else { return rest + block }
            return Array(rest[...index]) + block + Array(rest[(index + 1)...])
        }
    }
}
